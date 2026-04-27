require "test_helper"

module Importing
  module LlmEnrichment
    class ImporterTest < ActiveSupport::TestCase
      FakeClient = Struct.new(:responses, :model, :captured_inputs, keyword_init: true) do
        def create!(input:, text_format:)
          raise "missing input" if input.blank?
          raise "missing schema" if text_format.blank?

          self.captured_inputs ||= []
          captured_inputs << input
          responses.shift || raise("no fake response left")
        end
      end

      FakeLinkValidationResult = Struct.new(
        :accepted,
        :sanitized_url,
        :status,
        :final_url,
        :http_status,
        :error_class,
        :matched_phrase,
        :checked_at,
        keyword_init: true
      ) do
        def accepted? = accepted
        def unverifiable? = status == "kept_unverifiable"
        def rejected? = status.to_s.start_with?("rejected_")

        def as_json(*)
          {
            status: status,
            final_url: final_url,
            http_status: http_status,
            error_class: error_class,
            matched_phrase: matched_phrase,
            checked_at: checked_at&.iso8601
          }.compact
        end
      end

      FakeLinkValidator = Struct.new(:results_by_url) do
        def call(url:, field_name:)
          results_by_url.fetch(url) do
            FakeLinkValidationResult.new(
              accepted: true,
              sanitized_url: url,
              status: "ok",
              final_url: url,
              http_status: 200,
              checked_at: Time.current
            )
          end
        end
      end

      FakeLinkFinder = Struct.new(:results_by_event_id, :calls, keyword_init: true) do
        def call(event:)
          self.calls ||= []
          calls << event.id
          results_by_event_id.fetch(event.id) { default_result }
        end

        private

        def default_result
          LinkFinder::Result.new(
            payload: {
              "web_search_provider" => "serpapi",
              "queries" => [],
              "fields" => Importer::SEARCH_LINK_FIELDS.index_with do
                {
                  "query_name" => nil,
                  "query" => nil,
                  "provider" => "serpapi",
                  "search_id" => nil,
                  "candidates" => []
                }
              end.deep_stringify_keys
            },
            web_search_request_count: 0,
            web_search_candidate_count: 0
          )
        end
      end

      setup do
        @source = import_sources(:two)
        @run = @source.import_runs.create!(
          source_type: "llm_enrichment",
          status: "running",
          started_at: 1.minute.ago,
          metadata: {}
        )
      end

      teardown do
        AppSetting.reset_cache!
      end

      test "processes one openai call per future event and persists enrichments" do
        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            response_for(
              event_id: events(:published_one).id,
              genre: [ "Indie", "Pop" ],
              venue: "LKA Longhorn",
              event_description: "Event eins",
              venue_description: "Venue eins",
              homepage_link: "https://example.com/one"
            ),
            response_for(
              event_id: events(:needs_review_one).id,
              genre: [ "Rock" ],
              venue: "Im Wizemann",
              event_description: "Event zwei",
              venue_description: "Venue zwei"
            ),
            response_for(
              event_id: events(:needs_review_two).id,
              genre: [ "Show" ],
              venue: "Im Wizemann",
              event_description: "Event drei",
              venue_description: "Venue drei"
            )
          ]
        )
        link_finder = FakeLinkFinder.new(
          results_by_event_id: {
            events(:published_one).id => search_context_result(homepage_link: [ candidate("https://example.com/one") ]),
            events(:needs_review_one).id => search_context_result,
            events(:needs_review_two).id => search_context_result
          },
          calls: []
        )

        result = build_importer(client: client, link_finder: link_finder).call

        assert_equal 3, result.selected_count
        assert_equal 0, result.skipped_count
        assert_equal 3, result.enriched_count
        assert_equal 3, result.api_calls_count
        assert_equal 3, result.api_calls_completed_count
        assert_equal 3, client.captured_inputs.size
        published_enrichment = events(:published_one).reload.llm_enrichment
        assert_equal [ "Indie", "Pop" ], published_enrichment.genre
        assert_equal "https://example.com/one", published_enrichment.homepage_link
        assert_equal client.captured_inputs.first, published_enrichment.raw_response["llm_prompt"]
        assert_equal events(:published_one).id, published_enrichment.raw_response.dig("llm_raw_result", "event_id")
        assert_equal [], events(:needs_review_two).reload.llm_enrichment.genre
        assert_nil events(:published_past_one).reload.llm_enrichment
      end

      test "reloads llm prompt settings from the database before a run starts" do
        original_prompt = <<~TEXT.strip
          ALT search_results candidates homepage_link instagram_link facebook_link youtube_link
          venue_external_url
          {{input_json}}
        TEXT
        updated_prompt = <<~TEXT.strip
          NEU search_results candidates homepage_link instagram_link facebook_link youtube_link
          venue_external_url
          {{input_json}}
        TEXT
        prompt_setting = AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: original_prompt)
        AppSetting.reset_cache!
        AppSetting.llm_enrichment_prompt_template
        prompt_setting.update_column(:value, updated_prompt)

        event = events(:published_one)
        @run.update!(metadata: @run.metadata.merge("target_event_id" => event.id, "refresh_existing" => true))
        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            response_for(
              event_id: event.id,
              genre: [ "Indie" ],
              venue: "LKA Longhorn",
              event_description: "Event eins",
              venue_description: "Venue eins"
            )
          ]
        )

        build_importer(client: client, link_finder: FakeLinkFinder.new(results_by_event_id: { event.id => search_context_result }, calls: [])).call

        assert_includes client.captured_inputs.first, "NEU search_results candidates homepage_link instagram_link facebook_link youtube_link"
        assert_not_includes client.captured_inputs.first, "ALT search_results candidates homepage_link instagram_link facebook_link youtube_link"
      end

      test "includes truncated event_info and search result context in single-event prompt payload" do
        long_event_info = "ä" * 1005
        event = events(:published_one)
        event.update!(event_info: long_event_info)
        @run.update!(metadata: @run.metadata.merge("target_event_id" => event.id, "refresh_existing" => true))

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            response_for(
              event_id: event.id,
              genre: [ "Indie" ],
              venue: "LKA Longhorn",
              event_description: "Event eins",
              venue_description: "Venue eins"
            )
          ]
        )
        link_finder = FakeLinkFinder.new(
          results_by_event_id: {
            event.id => search_context_result(
              homepage_link: [
                candidate(
                  "https://example.com/one",
                  title: "Official",
                  displayed_link: "example.com",
                  snippet: "Offizielle Seite",
                  source: "Website",
                  about_source_description: "Mehr Kontext",
                  languages: [ "de" ],
                  regions: [ "DE" ]
                )
              ]
            )
          },
          calls: []
        )

        build_importer(client: client, link_finder: link_finder).call

        input_payload = JSON.parse(client.captured_inputs.first.split("Input:\n", 2).last)
        assert_equal event.id, input_payload.fetch("event_id")
        assert_equal long_event_info[0, 1000], input_payload.fetch("event_info")
        candidate_payload = input_payload.dig("search_results", "fields", "homepage_link", "candidates", 0)
        assert_equal "Official", candidate_payload.fetch("title")
        assert_equal "https://example.com/one", candidate_payload.fetch("link")
        assert_equal "example.com", candidate_payload.fetch("displayed_link")
        assert_equal "Offizielle Seite", candidate_payload.fetch("snippet")
        assert_equal "Website", candidate_payload.fetch("source")
        assert_equal "Mehr Kontext", candidate_payload.fetch("about_source_description")
      end

      test "binds selected links to supplied candidates and validates venue external url" do
        event = events(:published_one)
        @run.update!(metadata: @run.metadata.merge("target_event_id" => event.id, "refresh_existing" => true))
        validation_result = FakeLinkValidationResult.new(
          accepted: false,
          sanitized_url: nil,
          status: "rejected_http_error",
          final_url: "https://venue.example/invalid",
          http_status: 404,
          checked_at: Time.current
        )
        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            response_for(
              event_id: event.id,
              genre: [ "Indie" ],
              venue: "LKA Longhorn",
              event_description: "Event eins",
              venue_description: "Venue eins",
              homepage_link: "https://example.com/not-supplied",
              venue_external_url: "https://venue.example/invalid"
            )
          ]
        )
        link_finder = FakeLinkFinder.new(
          results_by_event_id: {
            event.id => search_context_result(
              homepage_link: [ candidate("https://example.com/allowed") ]
            )
          },
          calls: []
        )
        result = build_importer(
          client: client,
          link_finder: link_finder,
          link_validator: FakeLinkValidator.new({ "https://venue.example/invalid" => validation_result })
        ).call

        enrichment = event.reload.llm_enrichment
        assert_equal 1, result.links_checked_count
        assert_equal 1, result.links_rejected_count
        assert_nil enrichment.homepage_link
        assert_nil enrichment.venue_external_url
        assert_equal "not_in_supplied_candidates", enrichment.raw_response.dig("link_selection", "fields", "homepage_link", "rejection_reason")
        assert_nil enrichment.raw_response.dig("link_selection", "fields", "venue_external_url")
        assert_equal "rejected_http_error", enrichment.raw_response.dig("link_validation", "venue_external_url", "status")
      end

      test "stores venue external url from llm response without supplied search candidate" do
        event = events(:published_one)
        @run.update!(metadata: @run.metadata.merge("target_event_id" => event.id, "refresh_existing" => true))
        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            response_for(
              event_id: event.id,
              genre: [ "Indie" ],
              venue: "LKA Longhorn",
              event_description: "Event eins",
              venue_description: "Venue eins",
              venue_external_url: "https://venue.example"
            )
          ]
        )

        result = build_importer(
          client: client,
          link_finder: FakeLinkFinder.new(results_by_event_id: { event.id => search_context_result }, calls: [])
        ).call

        enrichment = event.reload.llm_enrichment
        assert_equal "https://venue.example", enrichment.venue_external_url
        assert_equal 1, result.links_checked_count
        assert_nil enrichment.raw_response.dig("search_context", "fields", "venue_external_url")
        assert_nil enrichment.raw_response.dig("link_selection", "fields", "venue_external_url")
        assert_equal "ok", enrichment.raw_response.dig("link_validation", "venue_external_url", "status")
      end

      test "refresh_existing overwrites an existing enrichment via single event call" do
        event = events(:published_past_one)
        existing_enrichment = EventLlmEnrichment.create!(
          event: event,
          source_run: import_runs(:one),
          genre: [ "Alt" ],
          venue: "Alt",
          event_description: "Alt",
          venue_description: "Alt",
          model: "existing-model",
          prompt_version: "v1",
          raw_response: { "event_id" => event.id }
        )
        @run.update!(
          metadata: @run.metadata.merge(
            "trigger_scope" => "single_event",
            "target_event_id" => event.id,
            "refresh_existing" => true
          )
        )
        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            response_for(
              event_id: event.id,
              genre: [ "Jazz" ],
              venue: "Neue Venue",
              event_description: "Neu",
              venue_description: "Neu",
              homepage_link: "https://example.com/past"
            )
          ]
        )
        link_finder = FakeLinkFinder.new(
          results_by_event_id: {
            event.id => search_context_result(homepage_link: [ candidate("https://example.com/past") ])
          },
          calls: []
        )

        result = build_importer(client: client, link_finder: link_finder).call

        updated_enrichment = event.reload.llm_enrichment
        assert_equal 1, result.api_calls_count
        assert_equal existing_enrichment.id, updated_enrichment.id
        assert_equal [ "Jazz" ], updated_enrichment.genre
        assert_equal "https://example.com/past", updated_enrichment.homepage_link
      end

      test "runs successfully with zero api calls when no future events need enrichment" do
        [ events(:published_one), events(:needs_review_one), events(:needs_review_two) ].each do |event|
          EventLlmEnrichment.create!(
            event: event,
            source_run: import_runs(:one),
            genre: [ "Existing" ],
            model: "existing-model",
            prompt_version: "v1",
            raw_response: { "event_id" => event.id }
          )
        end

        result = build_importer(client: FakeClient.new(model: "gpt-5-mini", responses: [])).call

        assert_equal 3, result.selected_count
        assert_equal 3, result.skipped_count
        assert_equal 0, result.enriched_count
        assert_equal 0, result.api_calls_count
        assert_equal 0, result.api_calls_completed_count
      end

      test "filters meta genres and stores rejected terms in raw response" do
        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            response_for(
              event_id: events(:published_one).id,
              genre: [ "Show", "Indie" ],
              venue: "LKA Longhorn",
              event_description: "Event eins",
              venue_description: "Venue eins"
            ),
            response_for(
              event_id: events(:needs_review_one).id,
              genre: [ "Concert", "Live Event" ],
              venue: "Im Wizemann",
              event_description: "Event zwei",
              venue_description: "Venue zwei"
            ),
            response_for(
              event_id: events(:needs_review_two).id,
              genre: [ "Comedy" ],
              venue: "Im Wizemann",
              event_description: "Event drei",
              venue_description: "Venue drei"
            )
          ]
        )

        result = build_importer(client: client).call

        assert_equal 3, result.enriched_count
        first_enrichment = events(:published_one).reload.llm_enrichment
        assert_equal [ "Indie" ], first_enrichment.genre
        assert_equal [ "Show" ], first_enrichment.raw_response.dig("genre_filter", "rejected_terms")
      end

      test "returns canceled result when stop was requested after response before persist" do
        target_event_id = events(:published_one).id

        client = Class.new do
          attr_reader :model

          def initialize(run, target_event_id)
            @run = run
            @model = "gpt-5-mini"
            @target_event_id = target_event_id
          end

          def create!(input:, text_format:)
            raise "missing input" if input.blank?
            raise "missing schema" if text_format.blank?

            @run.update!(metadata: @run.metadata.merge("stop_requested" => true, "stop_requested_at" => Time.current.iso8601))
            {
              "output_text" => {
                event_id: @target_event_id,
                genre: [ "Indie" ],
                venue: "LKA Longhorn",
                event_description: "Event eins",
                venue_description: "Venue eins",
                homepage_link: nil,
                instagram_link: nil,
                facebook_link: nil,
                youtube_link: nil,
                venue_external_url: nil,
                venue_address: nil
              }.to_json
            }
          end
        end.new(@run, target_event_id)

        result = build_importer(client: client).call

        assert_equal true, result.canceled
        assert_equal 0, result.enriched_count
        assert_equal 1, result.api_calls_completed_count
        assert_nil events(:published_one).reload.llm_enrichment
      end

      private

      def build_importer(client:, link_validator: FakeLinkValidator.new({}), link_finder: FakeLinkFinder.new(results_by_event_id: {}, calls: []))
        Importer.new(run: @run, client: client, link_validator: link_validator, link_finder: link_finder)
      end

      def response_for(
        event_id:,
        genre:,
        venue:,
        event_description:,
        venue_description:,
        homepage_link: nil,
        instagram_link: nil,
        facebook_link: nil,
        youtube_link: nil,
        venue_external_url: nil,
        venue_address: nil
      )
        {
          "output_text" => {
            event_id: event_id,
            genre: genre,
            venue: venue,
            event_description: event_description,
            venue_description: venue_description,
            homepage_link: homepage_link,
            instagram_link: instagram_link,
            facebook_link: facebook_link,
            youtube_link: youtube_link,
            venue_external_url: venue_external_url,
            venue_address: venue_address
          }.to_json
        }
      end

      def search_context_result(**field_candidates)
        LinkFinder::Result.new(
          payload: {
            "web_search_provider" => "serpapi",
            "queries" => [],
            "fields" => Importer::SEARCH_LINK_FIELDS.index_with do |field_name|
              {
                "query_name" => field_name.to_s,
                "query" => "query for #{field_name}",
                "provider" => "serpapi",
                "search_id" => "search-#{field_name}",
                "candidates" => Array(field_candidates[field_name]).map(&:deep_stringify_keys)
              }
            end.deep_stringify_keys
          },
          web_search_request_count: field_candidates.size,
          web_search_candidate_count: field_candidates.values.sum { |value| Array(value).size }
        )
      end

      def candidate(link, title: "Candidate", displayed_link: nil, snippet: "Snippet", source: "Website", about_source_description: nil, languages: nil, regions: nil)
        {
          "position" => 1,
          "title" => title,
          "link" => link,
          "displayed_link" => displayed_link,
          "snippet" => snippet,
          "source" => source,
          "about_source_description" => about_source_description,
          "languages" => languages,
          "regions" => regions
        }.compact
      end
    end
  end
end
