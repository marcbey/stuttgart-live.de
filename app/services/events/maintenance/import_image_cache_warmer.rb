module Events
  module Maintenance
    class ImportImageCacheWarmer
      Result = Data.define(
        :images_scanned,
        :images_eligible,
        :jobs_enqueued,
        :images_skipped_cached,
        :images_skipped_invalid,
        :images_skipped_failed
      )

      VALID_SCOPES = %w[published all].freeze

      def self.call(scope: "published", include_failed: false, limit: nil)
        new(scope:, include_failed:, limit:).call
      end

      def initialize(scope:, include_failed:, limit:)
        @scope = normalize_scope(scope)
        @include_failed = ActiveModel::Type::Boolean.new.cast(include_failed)
        @limit = normalize_limit(limit)
      end

      def call
        counts = {
          images_scanned: 0,
          images_eligible: 0,
          jobs_enqueued: 0,
          images_skipped_cached: 0,
          images_skipped_invalid: 0,
          images_skipped_failed: 0
        }

        each_candidate do |image|
          counts[:images_scanned] += 1

          if image.cached?
            counts[:images_skipped_cached] += 1
            next
          end

          unless image.image_url.to_s.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
            counts[:images_skipped_invalid] += 1
            next
          end

          if image.failed? && !include_failed?
            counts[:images_skipped_failed] += 1
            next
          end

          counts[:images_eligible] += 1
          Importing::CacheImportEventImageJob.perform_later(image.id, image.image_url)
          counts[:jobs_enqueued] += 1
        end

        Result.new(**counts)
      end

      private

      attr_reader :include_failed, :limit, :scope

      def include_failed?
        @include_failed
      end

      def each_candidate(&block)
        relation = base_relation
        relation = relation.limit(limit) if limit.present?
        relation.find_each(&block)
      end

      def base_relation
        relation = ImportEventImage.order(:id)
        return relation unless scope == "published"

        relation
          .where(import_class: "Event")
          .joins("INNER JOIN events ON events.id = import_event_images.import_event_id")
          .merge(Event.published_live)
      end

      def normalize_scope(value)
        normalized = value.to_s.strip.presence || "published"
        return normalized if VALID_SCOPES.include?(normalized)

        raise ArgumentError, "Ungültiger Scope #{normalized.inspect}. Erlaubt sind: #{VALID_SCOPES.join(', ')}"
      end

      def normalize_limit(value)
        return nil if value.blank?

        Integer(value).tap do |parsed|
          raise ArgumentError, "LIMIT muss größer als 0 sein" unless parsed.positive?
        end
      end
    end
  end
end
