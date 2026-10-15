module LegacyRedirects
  class Resolver
    Result = Data.define(:status, :destination, :reason, :score)
    NEGATIVE_TTL = 15.minutes

    def self.call(path:, query: "")
      new(path).call
    end

    def initialize(path)
      @path = SourceKey.normalize(path)
    end

    def call
      return missing unless path

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rule = LegacyRedirect.find_by(source_path: path)
      return stored_result(rule) if rule&.manual? || rule&.disabled?
      if rule&.redirect?
        result = stored_result(rule)
        return result if result.status == :redirect && rule.checked_at.present?

        rule.with_lock do
          return stored_result(rule) if rule.manual? || rule.disabled?

          rule.update!(status: "unresolved", target: nil, target_path: nil, checked_at: nil, retry_at: nil)
        end
      end

      version = Invalidation.version
      return missing if negative_fresh?(rule, version)
      return missing if rule.nil? && Rails.cache.read(negative_key(version))

      rule ||= LegacyRedirect.new(source_path: path, source_kind: inferred_kind)
      evidence = [ rule.source_kind, rule.source_metadata.deep_dup ]
      match = Matcher.call(rule)
      if match && Target.path_for(LegacyRedirect.new(target: match.target, target_path: match.target_path)).present?
        return persist_match(rule, match, evidence: evidence)
      end

      retry_at = [ Time.current + NEGATIVE_TTL, Invalidation.next_publication_at(Time.current) ].min
      if rule.persisted?
        rule.with_lock do
          return stored_result(rule) if rule.manual? || rule.disabled? || rule.redirect?
          return missing if [ rule.source_kind, rule.source_metadata ] != evidence

          rule.update!(status: "unresolved", checked_at: Time.current, retry_at: retry_at, resolution_version: version)
        end
      else
        Rails.cache.write(negative_key(version), true, expires_in: [ retry_at - Time.current, 0.01 ].max)
      end
      missing
    ensure
      if started
        ActiveSupport::Notifications.instrument("resolve.legacy_redirects", path: path,
          duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000)
      end
    end

    private

    attr_reader :path

    def stored_result(rule)
      return Result.new(:disabled, nil, "manual_block", nil) if rule.disabled?
      return missing unless rule.redirect?

      destination = Target.path_for(rule)
      return missing if destination.blank? || destination == path

      Result.new(:redirect, destination, rule.match_reason, rule.score&.to_f)
    end

    def persist_match(rule, match, evidence:)
      if rule.new_record?
        LegacyRedirect.insert_all([ { source_path: path, source_kind: rule.source_kind } ],
          unique_by: :index_legacy_redirects_on_source_path)
        rule = LegacyRedirect.find_by!(source_path: path)
      end
      rule.with_lock do
        return stored_result(rule) if rule.manual? || rule.disabled? || rule.redirect?
        return missing if [ rule.source_kind, rule.source_metadata ] != evidence

        rule.update!(target: match.target, target_path: match.target_path, status: "redirect", origin: "automatic",
          match_reason: match.reason, score: match.score, checked_at: Time.current, retry_at: nil, resolution_version: Invalidation.version)
      end
      stored_result(rule)
    end

    def negative_fresh?(rule, version)
      rule&.checked_at && rule.checked_at > NEGATIVE_TTL.ago &&
        (rule.retry_at.nil? || rule.retry_at > Time.current) && rule.resolution_version == version
    end

    def negative_key(version)
      "legacy_redirects/missing/#{version}/#{Digest::SHA256.hexdigest(path)}"
    end

    def inferred_kind
      case path
      when %r{\A/events/} then "event"
      when %r{\A/(?:blog|news)/} then "news"
      when %r{\A/genre/} then "genre"
      when %r{\A/wp-content/uploads/} then "file"
      else "page"
      end
    end

    def missing
      Result.new(:not_found, nil, nil, nil)
    end
  end
end
