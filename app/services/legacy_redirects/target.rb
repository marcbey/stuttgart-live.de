module LegacyRedirects
  class Target
    ALLOWED_TYPES = %w[Event BlogPost StaticPage Genre ActiveStorage::Blob].freeze
    FIXED_PATHS = %w[/ /events /news /deine-events /highlights /alles-aus-stuttgart /tagestipp /unter-30 /russ-live /begleitformular /newsletter_subscribers/new].freeze
    EVENT_MEDIA = %w[promotion_banner_image promotion_banner_landscape_image highlight_video_file highlight_landscape_video_file].freeze
    POST_MEDIA = %w[cover_image promotion_banner_image promotion_banner_landscape_image].freeze

    class << self
      def resolve(value)
        path = SourceKey.normalize(value, allow_internal: true)
        return unless path
        return blob_result(path) if path.start_with?("/media/", "/rails/active_storage/blobs/proxy/")
        return if SourceKey.forbidden?(path)
        return { target: nil, target_path: path } if FIXED_PATHS.include?(path)

        record = record_for(path)
        return unless record && canonical_path(record) == path

        { target: record, target_path: nil }
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound, URI::InvalidURIError
        nil
      end

      def path_for(rule)
        return unless rule.target_type.blank? || ALLOWED_TYPES.include?(rule.target_type)
        return resolve(rule.target_path)&.fetch(:target_path) if rule.target_type.blank? && rule.target_id.blank?
        return if rule.target_path.present?

        record = rule.target
        return unless record&.persisted? && !record.destroyed?

        record = record.class.find_by(id: record.id)
        canonical_path(record) if record
      end

      private

      def record_for(path)
        case path
        when %r{\A/events/([^/]+)\z} then Event.published_live.find_by(slug: $1)
        when %r{\A/news/([^/]+)\z} then BlogPost.published_live.find_by(slug: $1)
        when %r{\A/([^/]+)\z}
          slug = $1
          if Public::Events::LaneDirectory.routeable_genre_slug?(slug)
            Genre.find_by(slug: slug)
          else
            StaticPage.find_by(slug: slug)
          end
        end
      end

      def canonical_path(record)
        path = candidate_path(record)
        return path if record.is_a?(ActiveStorage::Blob)
        return unless path && canonical_route?(record, path)

        path
      end

      def candidate_path(record)
        case record
        when Event
          helpers.event_path(record.slug) if Event.published_live.exists?(id: record.id)
        when BlogPost
          helpers.news_path(record.slug) if BlogPost.published_live.exists?(id: record.id)
        when StaticPage
          helpers.static_page_path(record.slug)
        when Genre
          Public::Events::LaneDirectory.public_path_for_genre_slug(record.slug)
        when ActiveStorage::Blob
          blob_path(record)
        end
      end

      def canonical_route?(record, path)
        route = recognized_route(path)
        return false unless route
        expected = case record
        when Event then { controller: "public/events", action: "show", slug: record.slug }
        when BlogPost then { controller: "public/news", action: "show", slug: record.slug }
        when StaticPage then { controller: "public/pages", action: "show", slug: record.slug }
        when Genre then { controller: "public/events", action: "lane", lane_slug: record.slug }
        end
        expected && expected.all? { |key, value| route[key] == value }
      rescue ActionController::RoutingError
        false
      end

      def recognized_route(path)
        request = ActionDispatch::Request.new(Rack::MockRequest.env_for(path, method: "GET"))
        Rails.application.routes.router.recognize(request) do |route, parameters|
          request.path_parameters = parameters
          return parameters if route.app.matches?(request) && route.app.dispatcher?
        end
        nil
      end

      def blob_path(blob)
        return unless blob.service.is_a?(ActiveStorage::Service::DiskService)
        return unless blob.attachments.any? { |attachment| public_attachment?(attachment) }
        return unless blob.service.exist?(blob.key)

        PublicMediaUrl.path_for(blob) || helpers.rails_storage_proxy_path(blob, only_path: true)
      end

      def public_attachment?(attachment)
        record = attachment.record
        case record
        when EventImage
          attachment.name == "file" && Event.published_live.exists?(id: record.event_id)
        when Event
          EVENT_MEDIA.include?(attachment.name) && Event.published_live.exists?(id: record.id)
        when BlogPost
          POST_MEDIA.include?(attachment.name) && BlogPost.published_live.exists?(id: record.id)
        when ActionText::RichText
          attachment.name == "embeds" && record.name == "body" && public_rich_text_owner?(record.record)
        end
      end

      def public_rich_text_owner?(owner)
        owner.is_a?(StaticPage) || (owner.is_a?(BlogPost) && BlogPost.published_live.exists?(id: owner.id))
      end

      def blob_result(path)
        blob = if path.start_with?("/rails/active_storage/blobs/proxy/")
          signed_id = path.split("/")[5]
          ActiveStorage::Blob.find_signed(signed_id)
        else
          signature, first, second, key, = path.delete_prefix("/media/").split("/")
          relative = [ first, second, key ].join("/")
          expected = PublicMediaUrl.signature_for(relative_path: relative)
          ActiveStorage::Blob.find_by(key: key) if ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
        end
        return unless blob && blob_path(blob)

        { target: blob, target_path: nil }
      end

      def helpers
        Rails.application.routes.url_helpers
      end
    end
  end
end
