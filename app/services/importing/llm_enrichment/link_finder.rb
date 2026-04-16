require "uri"

module Importing
  module LlmEnrichment
    class LinkFinder
      LINK_FIELDS = %i[homepage_link instagram_link facebook_link youtube_link].freeze
      GOOGLE_RESULT_LIMIT = 10
      HOMEPAGE_BLOCKED_HOST_FRAGMENTS = %w[
        bandsintown
        eventim
        facebook
        instagram
        reservix
        songkick
        spotify
        stuttgart-live
        ticket
        youtube
      ].freeze
      INSTAGRAM_RESERVED_PATHS = %w[accounts explore p reel reels stories tv].freeze
      FACEBOOK_RESERVED_PATHS = %w[events groups login permalink.php photo photos posts reels share watch].freeze
      YOUTUBE_ALLOWED_PATH_PREFIXES = %w[@ c channel user].freeze

      Result = Data.define(
        :links,
        :payload,
        :search_count,
        :candidate_count,
        :found_count,
        :null_count,
        :validation_results
      )

      def initialize(
        serpapi_client: SerpApiClient.new,
        query_builder: QueryBuilder.new,
        link_validator: LinkValidator.new
      )
        @serpapi_client = serpapi_client
        @query_builder = query_builder
        @link_validator = link_validator
      end

      def call(event:)
        queries_payload = []
        candidates_by_field = LINK_FIELDS.index_with { [] }

        query_builder.call(event: event).each do |query|
          queries_payload << run_query(event:, query:, candidates_by_field:)
        end

        validation_results = []
        fields_payload = {}
        links = {}
        candidate_count = 0
        found_count = 0

        LINK_FIELDS.each do |field_name|
          candidates = candidates_by_field.fetch(field_name).sort_by do |candidate|
            [ -(candidate["score"] || -1), candidate["position"] || GOOGLE_RESULT_LIMIT, candidate["url"].to_s ]
          end
          candidate_count += candidates.size

          selected_url = nil

          candidates.each do |candidate|
            next if candidate["rejection_reason"].present?

            if social_field?(field_name)
              candidate["selected"] = true
              candidate["selection_strategy"] = "search_profile_match"
              selected_url = candidate.fetch("url")
              break
            end

            validation = link_validator.call(url: candidate.fetch("url"), field_name:)
            validation_results << validation
            candidate["validation"] = validation.as_json

            if validation.accepted?
              candidate["selected"] = true
              selected_url = validation.sanitized_url
              break
            end

            candidate["rejection_reason"] = validation.status
          end

          fields_payload[field_name.to_s] = {
            "selected_url" => selected_url,
            "candidates" => candidates
          }
          links[field_name] = selected_url
          found_count += 1 if selected_url.present?
        end

        Result.new(
          links: links,
          payload: {
            "queries" => queries_payload,
            "fields" => fields_payload
          },
          search_count: queries_payload.size,
          candidate_count: candidate_count,
          found_count: found_count,
          null_count: LINK_FIELDS.size - found_count,
          validation_results: validation_results
        )
      end

      private

      attr_reader :link_validator, :query_builder, :serpapi_client

      def social_field?(field_name)
        %i[instagram_link facebook_link].include?(field_name)
      end

      def run_query(event:, query:, candidates_by_field:)
        search_result = serpapi_client.search(query: query.query, num: GOOGLE_RESULT_LIMIT)
        Array(search_result.organic_results).each do |organic_result|
          candidate = build_candidate(
            event: event,
            field_name: query.field_name.to_sym,
            organic_result: organic_result,
            query: query,
            search_id: search_result.search_id
          )
          candidates_by_field.fetch(query.field_name.to_sym) << candidate if candidate.present?
        end

        {
          "name" => query.name,
          "field_name" => query.field_name.to_s,
          "query" => query.query,
          "search_id" => search_result.search_id
        }
      rescue SerpApiClient::Error => e
        {
          "name" => query.name,
          "field_name" => query.field_name.to_s,
          "query" => query.query,
          "error_class" => e.class.to_s,
          "error_message" => e.message
        }
      end

      def build_candidate(event:, field_name:, organic_result:, query:, search_id:)
        uri = parse_http_uri(organic_result.link)
        return if uri.blank?

        normalized_url = normalize_candidate_url(uri, field_name:)
        return if normalized_url.blank?

        score = score_candidate(event:, field_name:, uri:, title: organic_result.title, snippet: organic_result.snippet)
        rejection_reason = rejection_reason_for(event:, field_name:, uri:, score:)

        {
          "url" => normalized_url,
          "title" => organic_result.title,
          "snippet" => organic_result.snippet,
          "position" => organic_result.position,
          "query_name" => query.name,
          "search_id" => search_id,
          "score" => score,
          "rejection_reason" => rejection_reason
        }.compact
      end

      def parse_http_uri(value)
        uri = URI.parse(value)
        return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return if uri.host.blank?

        uri
      rescue URI::InvalidURIError
        nil
      end

      def normalize_candidate_url(uri, field_name:)
        normalized_uri = uri.dup
        normalized_uri.fragment = nil
        normalized_uri.query = nil unless keep_query?(field_name, normalized_uri)
        normalized_uri.to_s
      end

      def keep_query?(field_name, uri)
        field_name == :facebook_link && uri.path.to_s == "/profile.php"
      end

      def rejection_reason_for(event:, field_name:, uri:, score:)
        case field_name
        when :homepage_link
          homepage_rejection_reason(event:, uri:, score:)
        when :instagram_link
          instagram_rejection_reason(uri:) || weak_match_rejection(score)
        when :facebook_link
          facebook_rejection_reason(uri:) || weak_match_rejection(score)
        when :youtube_link
          youtube_rejection_reason(uri:) || weak_match_rejection(score)
        end
      end

      def homepage_rejection_reason(event:, uri:, score:)
        host = normalized_host(uri)
        return "blocked_homepage_domain" if homepage_blocked_host?(host)
        return "host_mismatch" unless host_matches_known_identity?(host, event)
        return "weak_match" if score < 9

        nil
      end

      def instagram_rejection_reason(uri:)
        return "wrong_host" unless %w[instagram.com www.instagram.com].include?(normalized_host(uri))

        segments = path_segments(uri)
        return "non_profile_path" unless segments.size == 1
        return "reserved_path" if INSTAGRAM_RESERVED_PATHS.include?(segments.first.downcase)

        nil
      end

      def facebook_rejection_reason(uri:)
        return "wrong_host" unless %w[facebook.com www.facebook.com].include?(normalized_host(uri))

        return nil if uri.path.to_s == "/profile.php" && uri.query.to_s.include?("id=")

        segments = path_segments(uri)
        return "non_profile_path" unless segments.size == 1
        return "reserved_path" if FACEBOOK_RESERVED_PATHS.include?(segments.first.downcase)

        nil
      end

      def youtube_rejection_reason(uri:)
        return "wrong_host" unless %w[youtube.com www.youtube.com].include?(normalized_host(uri))

        segments = path_segments(uri)
        return "non_channel_path" if segments.blank?

        first_segment = segments.first
        return nil if first_segment.start_with?("@")
        return nil if YOUTUBE_ALLOWED_PATH_PREFIXES.include?(first_segment.downcase) && segments.second.present?

        "non_channel_path"
      end

      def weak_match_rejection(score)
        "weak_match" if score < 6
      end

      def score_candidate(event:, field_name:, uri:, title:, snippet:)
        handle = candidate_handle(field_name:, uri:)
        title_text = normalized_text(title)
        snippet_text = normalized_text(snippet)
        score = 0

        score += 10 if exact_handle_match?(handle, event)
        score += 6 if partial_handle_match?(handle, event)
        score += 4 if title_identity_match?(title_text, event)
        score += 2 if snippet_identity_match?(snippet_text, event)
        score += 3 if field_name == :homepage_link && host_matches_known_identity?(uri, event)

        score
      end

      def candidate_handle(field_name:, uri:)
        case field_name
        when :homepage_link
          normalized_text(host_label(uri))
        when :instagram_link, :facebook_link
          path_segments(uri).first.to_s.delete_prefix("@").downcase
        when :youtube_link
          segments = path_segments(uri)
          value = segments.first.to_s.start_with?("@") ? segments.first : segments.second
          value.to_s.delete_prefix("@").downcase
        else
          ""
        end
      end

      def host_matches_known_identity?(host, event)
        host_label = if host.respond_to?(:host)
          normalized_text(self.host_label(host))
        else
          normalized_text(host.to_s.sub(/\Awww\./, "").split(".").first.to_s)
        end

        known_handles(event).any? do |candidate|
          host_label.include?(candidate) || candidate.include?(host_label)
        end
      end

      def exact_handle_match?(handle, event)
        known_handles(event).include?(normalize_handle(handle))
      end

      def partial_handle_match?(handle, event)
        normalized_handle = normalize_handle(handle)
        known_handles(event).any? do |candidate|
          normalized_handle.include?(candidate) || candidate.include?(normalized_handle)
        end
      end

      def title_identity_match?(text, event)
        identity_texts(event).any? { |candidate| text.include?(candidate) }
      end

      def snippet_identity_match?(text, event)
        identity_texts(event).any? { |candidate| text.include?(candidate) }
      end

      def homepage_blocked_host?(host)
        HOMEPAGE_BLOCKED_HOST_FRAGMENTS.any? { |fragment| host.include?(fragment) }
      end

      def known_handles(event)
        @known_handles ||= {}
        @known_handles[event.id] ||= [ event.artist_name, event.title, event.venue ].flat_map do |value|
          build_handle_variants(value)
        end.uniq
      end

      def identity_texts(event)
        @identity_texts ||= {}
        @identity_texts[event.id] ||= [ event.artist_name, event.title, event.venue ].filter_map do |value|
          normalized = normalized_text(value)
          normalized.presence
        end
      end

      def build_handle_variants(value)
        normalized = normalized_text(value)
        return [] if normalized.blank?

        tokens = normalized.split
        variants = [ normalized.delete(" ") ]
        variants.concat(tokens.select { |token| token.length >= 4 })
        variants.concat(tokens.each_cons(2).map { |pair| pair.join })
        variants.map { |variant| normalize_handle(variant) }.reject(&:blank?).uniq
      end

      def normalized_host(uri)
        uri.host.to_s.downcase
      end

      def host_label(uri)
        normalized_host(uri).sub(/\Awww\./, "").split(".").first.to_s
      end

      def path_segments(uri)
        uri.path.to_s.split("/").reject(&:blank?)
      end

      def normalize_handle(value)
        normalized_text(value).delete(" ")
      end

      def normalized_text(value)
        ActiveSupport::Inflector.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
      end
    end
  end
end
