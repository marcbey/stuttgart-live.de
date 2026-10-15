module LegacyRedirects
  module Invalidation
    KEY = "legacy_redirects/generation".freeze
    MAX_AGE = 15.minutes
    module_function

    def version
      entry = Rails.cache.read(KEY)
      return entry[:token] if valid_entry?(entry)

      expire!
    end

    def expire!(record = nil)
      now = Time.current
      entry = Rails.cache.read(KEY)
      deadline = valid_entry?(entry) ? entry[:deadline] : next_publication_at(now)
      publication = record.published_at if record.respond_to?(:published_at) && record.respond_to?(:status) && record.status == "published"
      deadline = [ deadline, publication ].compact.select { |time| time > now }.min || now + MAX_AGE
      deadline = [ deadline, now + MAX_AGE ].min
      token = SecureRandom.uuid
      Rails.cache.write(KEY, { token: token, deadline: deadline }, expires_in: deadline - now)
      token
    end

    def valid_entry?(entry)
      entry.is_a?(Hash) && entry[:token].present? && entry[:deadline].respond_to?(:>) && entry[:deadline] > Time.current
    end

    def next_publication_at(now)
      [ Event, BlogPost ].filter_map do |model|
        model.where(status: "published").where("published_at > ?", now).minimum(:published_at)
      end.min || now + MAX_AGE
    end

    module ContentChanges
      extend ActiveSupport::Concern
      included do
        after_commit { LegacyRedirects::Invalidation.expire!(self) }
      end
    end
  end
end
