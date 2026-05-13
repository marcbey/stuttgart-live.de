module Public
  module Seo
    class PagePresenter
      DEFAULT_SITE_NAME = "Stuttgart Live"

      attr_reader :description, :canonical_url, :meta_title, :og_image_url, :og_type, :page_title, :robots

      def initialize(title:, description:, canonical_url:, meta_title: nil, og_image_url: nil, og_type: "website", robots: nil, json_ld: nil)
        @page_title = title.to_s
        @meta_title = meta_title.to_s.presence || @page_title.delete_suffix(" | #{DEFAULT_SITE_NAME}")
        @description = description.to_s.squish.truncate(160)
        @canonical_url = canonical_url.to_s
        @og_image_url = og_image_url.to_s.presence
        @og_type = og_type.to_s.presence || "website"
        @robots = robots.to_s.presence
        @json_ld = json_ld
      end

      def twitter_card
        og_image_url.present? ? "summary_large_image" : "summary"
      end

      def json_ld_payloads
        json_ld_entries.compact_blank.map do |payload|
          payload.is_a?(String) ? payload : payload.to_json
        end
      end

      private

      def json_ld_entries
        return [] if @json_ld.blank?
        return @json_ld if @json_ld.is_a?(Array)

        [ @json_ld ]
      end
    end
  end
end
