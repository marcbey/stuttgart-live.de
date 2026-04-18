require "test_helper"

module Importing
  module LlmEnrichment
    class ImporterTest < ActiveSupport::TestCase
      FakeClient = Struct.new(:responses, :model, keyword_init: true) do
        def create!(input:, text_format:)
          raise "missing input" if input.blank?
          raise "missing schema" if text_format.blank?

          responses.shift || raise("no fake response left")
        end
      end

      CapturingClient = Struct.new(:response, :model, :captured_input, keyword_init: true) do
        def create!(input:, text_format:)
          raise "missing input" if input.blank?
          raise "missing schema" if text_format.blank?

          self.captured_input = input
          response || raise("missing response")
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
          result = results_by_url.fetch(url) do
            FakeLinkValidationResult.new(
              accepted: true,
              sanitized_url: url,
              status: "ok",
              final_url: url,
              http_status: 200,
              checked_at: Time.current
            )
          end

          result
        end
      end

      FakeLinkFinder = Struct.new(:results_by_event_id, :calls, keyword_init: true) do
        def call(event:)
          self.calls ||= []
          calls << event.id
          results_by_event_id.fetch(event.id) do
            LinkFinder::Result.new(
              links: {
                youtube_link: nil,
                instagram_link: nil,
                homepage_link: nil,
                facebook_link: nil
              },
              payload: {
                "queries" => [],
                "fields" => {
                  "youtube_link" => { "selected_url" => nil, "candidates" => [] },
                  "instagram_link" => { "selected_url" => nil, "candidates" => [] },
                  "homepage_link" => { "selected_url" => nil, "candidates" => [] },
                  "facebook_link" => { "selected_url" => nil, "candidates" => [] }
                }
              },
              web_search_request_count: 0,
              web_search_candidate_count: 0,
              links_found_via_web_search_count: 0,
              links_null_after_link_lookup_count: 4,
              validation_results: []
            )
          end
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

      test "selects all future events without enrichment and persists enrichments" do
        freeze_time do
          link_finder = FakeLinkFinder.new(
            results_by_event_id: {
              events(:published_one).id => fake_link_lookup_result(homepage_link: "https://example.com/one")
            },
            calls: []
          )
          client = FakeClient.new(
            model: "gpt-5-mini",
            responses: [
              {
                "output_text" => {
                  events: [
                    {
                      event_id: events(:published_one).id,
                      genre: [ "Indie", "Pop" ],
                      venue: "LKA Longhorn",
                      event_description: "Event eins",
                      venue_description: "Venue eins",
                      venue_external_url: "https://venue.example/one",
                      venue_address: "Venueweg 1, Stuttgart",
                      youtube_link: "https://youtube.example/one",
                      instagram_link: "https://instagram.example/one",
                      homepage_link: "https://example.com/one",
                      facebook_link: "https://facebook.example/one"
                    },
                    {
                      event_id: events(:needs_review_one).id,
                      genre: [ "Rock" ],
                      venue: "Im Wizemann",
                      event_description: "Event zwei",
                      venue_description: "Venue zwei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: "https://example.com/two",
                      facebook_link: nil
                    },
                    {
                      event_id: events(:needs_review_two).id,
                      genre: [ "Show" ],
                      venue: "Im Wizemann",
                      event_description: "Event drei",
                      venue_description: "Venue drei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    }
                  ]
                }.to_json
              }
            ]
          )

          result = build_importer(client: client, link_finder: link_finder).call

          assert_equal 3, result.selected_count
          assert_equal 0, result.skipped_count
          assert_equal 3, result.enriched_count
          assert_equal 1, result.batches_count
          assert_nil result.merge_run_id
          assert_equal 0, result.web_search_request_count
          assert_equal 1, result.links_found_via_web_search_count

          enrichment = events(:published_one).reload.llm_enrichment
          assert_equal [ "Indie", "Pop" ], enrichment.genre
          assert_equal "https://venue.example/one", enrichment.venue_external_url
          assert_equal "Venueweg 1, Stuttgart", enrichment.venue_address
          assert_equal "https://example.com/one", enrichment.homepage_link
          assert_equal @run, enrichment.source_run

          assert_equal [ "Rock" ], events(:needs_review_one).reload.llm_enrichment.genre
          assert_equal [], events(:needs_review_two).reload.llm_enrichment.genre
          assert_nil events(:published_past_one).reload.llm_enrichment
        end
      end

      test "includes truncated event_info in input_json" do
        AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: "{{input_json}}")
        AppSetting.reset_cache!

        long_event_info = "ä" * 1005
        events(:published_one).update!(event_info: long_event_info)
        events(:needs_review_one).update!(event_info: "Kurze Beschreibung")
        events(:needs_review_two).update!(event_info: nil)

        client = CapturingClient.new(
          model: "gpt-5-mini",
          response: {
            "output_text" => {
              events: [
                {
                  event_id: events(:published_one).id,
                  genre: [ "Indie" ],
                  venue: "LKA Longhorn",
                  event_description: "Event eins",
                  venue_description: "Venue eins",
                  youtube_link: nil,
                  instagram_link: nil,
                  homepage_link: nil,
                  facebook_link: nil
                },
                {
                  event_id: events(:needs_review_one).id,
                  genre: [ "Rock" ],
                  venue: "Im Wizemann",
                  event_description: "Event zwei",
                  venue_description: "Venue zwei",
                  youtube_link: nil,
                  instagram_link: nil,
                  homepage_link: nil,
                  facebook_link: nil
                },
                {
                  event_id: events(:needs_review_two).id,
                  genre: [ "Show" ],
                  venue: "Im Wizemann",
                  event_description: "Event drei",
                  venue_description: "Venue drei",
                  youtube_link: nil,
                  instagram_link: nil,
                  homepage_link: nil,
                  facebook_link: nil
                }
              ]
            }.to_json
          }
        )

        build_importer(client: client).call

        input_payload = JSON.parse(client.captured_input)
        published_payload = input_payload.find { |item| item.fetch("event_id") == events(:published_one).id }
        review_payload = input_payload.find { |item| item.fetch("event_id") == events(:needs_review_one).id }
        empty_payload = input_payload.find { |item| item.fetch("event_id") == events(:needs_review_two).id }

        assert_equal long_event_info[0, 1000], published_payload.fetch("event_info")
        assert_equal 1000, published_payload.fetch("event_info").length
        assert_equal "Kurze Beschreibung", review_payload.fetch("event_info")
        assert_equal "", empty_payload.fetch("event_info")
      end

      test "validates links before persisting and stores validation details" do
        freeze_time do
          validation_results = [
            FakeLinkValidationResult.new(
              accepted: false,
              sanitized_url: nil,
              status: "rejected_http_error",
              http_status: 404,
              checked_at: Time.current
            ),
            FakeLinkValidationResult.new(
              accepted: true,
              sanitized_url: "https://facebook.example/final",
              status: "ok",
              final_url: "https://facebook.example/final",
              http_status: 200,
              checked_at: Time.current
            ),
            FakeLinkValidationResult.new(
              accepted: true,
              sanitized_url: "https://youtube.example/blocked",
              status: "kept_unverifiable",
              http_status: 429,
              checked_at: Time.current
            ),
            FakeLinkValidationResult.new(
              accepted: true,
              sanitized_url: "https://instagram.example/private",
              status: "kept_unverifiable",
              http_status: 403,
              checked_at: Time.current
            )
          ]
          link_finder = FakeLinkFinder.new(
            results_by_event_id: {
              events(:published_one).id => LinkFinder::Result.new(
                links: {
                  youtube_link: "https://youtube.example/blocked",
                  instagram_link: "https://instagram.example/private",
                  homepage_link: nil,
                  facebook_link: "https://facebook.example/final"
                },
                payload: {
                  "queries" => [ { "name" => "broad", "field_name" => "homepage_link", "query" => "\"Published Artist\" \"Published Event\" 2026" } ],
                  "fields" => {
                    "youtube_link" => {
                      "selected_url" => "https://youtube.example/blocked",
                      "candidates" => [
                        { "url" => "https://youtube.example/blocked", "validation" => validation_results[2].as_json }
                      ]
                    },
                    "instagram_link" => {
                      "selected_url" => "https://instagram.example/private",
                      "candidates" => [
                        { "url" => "https://instagram.example/private", "validation" => validation_results[3].as_json }
                      ]
                    },
                    "homepage_link" => {
                      "selected_url" => nil,
                      "candidates" => [
                        {
                          "url" => "https://example.com/missing",
                          "validation" => validation_results[0].as_json,
                          "rejection_reason" => "rejected_http_error"
                        }
                      ]
                    },
                    "facebook_link" => {
                      "selected_url" => "https://facebook.example/final",
                      "candidates" => [
                        { "url" => "https://facebook.example/final", "validation" => validation_results[1].as_json }
                      ]
                    }
                }
                },
                web_search_request_count: 4,
                web_search_candidate_count: 4,
                links_found_via_web_search_count: 3,
                links_null_after_link_lookup_count: 1,
                validation_results: validation_results
              )
            },
            calls: []
          )
          client = FakeClient.new(
            model: "gpt-5-mini",
            responses: [
              {
                "output_text" => {
                  events: [
                    {
                      event_id: events(:published_one).id,
                      genre: [ "Indie" ],
                      venue: "LKA Longhorn",
                      event_description: "Event eins",
                      venue_description: "Venue eins",
                      youtube_link: "https://youtube.example/blocked",
                      instagram_link: "https://instagram.example/private",
                      homepage_link: "https://example.com/missing",
                      facebook_link: "https://facebook.example/final"
                    },
                    {
                      event_id: events(:needs_review_one).id,
                      genre: [ "Rock" ],
                      venue: "Im Wizemann",
                      event_description: "Event zwei",
                      venue_description: "Venue zwei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    },
                    {
                      event_id: events(:needs_review_two).id,
                      genre: [ "Show" ],
                      venue: "Im Wizemann",
                      event_description: "Event drei",
                      venue_description: "Venue drei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    }
                  ]
                }.to_json
              }
            ]
          )

          result = build_importer(client: client, link_finder: link_finder).call

          assert_equal 4, result.links_checked_count
          assert_equal 1, result.links_rejected_count
          assert_equal 2, result.links_unverifiable_count
          assert_equal 4, result.web_search_request_count
          assert_equal 4, result.web_search_candidate_count
          assert_equal 3, result.links_found_via_web_search_count
          assert_equal 9, result.links_null_after_link_lookup_count

          enrichment = events(:published_one).reload.llm_enrichment
          assert_equal "https://youtube.example/blocked", enrichment.youtube_link
          assert_equal "https://instagram.example/private", enrichment.instagram_link
          assert_nil enrichment.homepage_link
          assert_equal "https://facebook.example/final", enrichment.facebook_link
          assert_equal "rejected_http_error", enrichment.raw_response.dig("link_lookup", "fields", "homepage_link", "candidates", 0, "rejection_reason")
          assert_equal 404, enrichment.raw_response.dig("link_lookup", "fields", "homepage_link", "candidates", 0, "validation", "http_status")
          assert_equal "kept_unverifiable", enrichment.raw_response.dig("link_lookup", "fields", "youtube_link", "candidates", 0, "validation", "status")
        end
      end

      test "skips future events that already have an enrichment and batches remaining events" do
        EventLlmEnrichment.create!(
          event: events(:needs_review_one),
          source_run: import_runs(:one),
          genre: [ "Pop" ],
          model: "existing-model",
          prompt_version: "v1",
          raw_response: { "event_id" => events(:needs_review_one).id }
        )

        stub_const("#{Importer}::BATCH_SIZE", 1) do
          freeze_time do
            client = FakeClient.new(
              model: "gpt-5-mini",
              responses: [
                {
                  "output_text" => {
                    events: [
                      {
                        event_id: events(:published_one).id,
                        genre: [ "Pop" ],
                        venue: "LKA Longhorn",
                        event_description: "Event eins",
                        venue_description: "Venue eins",
                        youtube_link: nil,
                        instagram_link: nil,
                        homepage_link: nil,
                        facebook_link: nil
                      }
                    ]
                  }.to_json
                },
                {
                  "output_text" => {
                    events: [
                      {
                        event_id: events(:needs_review_two).id,
                        genre: [ "Rock" ],
                        venue: "Im Wizemann",
                        event_description: "Event zwei",
                        venue_description: "Venue zwei",
                        youtube_link: nil,
                        instagram_link: nil,
                        homepage_link: nil,
                        facebook_link: nil
                      }
                    ]
                  }.to_json
                }
              ]
            )

            result = build_importer(client: client).call

            assert_equal 3, result.selected_count
            assert_equal 1, result.skipped_count
            assert_equal 2, result.enriched_count
            assert_equal 2, result.batches_count
          end
        end
      end

      test "refresh mode processes all future events and updates existing enrichments" do
        existing_enrichment = EventLlmEnrichment.create!(
          event: events(:needs_review_one),
          source_run: import_runs(:one),
          genre: [ "Pop" ],
          venue: "Alte Venue",
          event_description: "Alt",
          venue_description: "Alt",
          youtube_link: nil,
          instagram_link: nil,
          homepage_link: nil,
          facebook_link: nil,
          model: "existing-model",
          prompt_version: "v1",
          raw_response: { "event_id" => events(:needs_review_one).id, "genre" => [ "Pop" ] }
        )
        @run.update!(metadata: @run.metadata.merge("refresh_existing" => true))
        link_finder = FakeLinkFinder.new(
          results_by_event_id: {
            events(:published_one).id => fake_link_lookup_result(homepage_link: "https://example.com/one-refresh"),
            events(:needs_review_one).id => fake_link_lookup_result(
              homepage_link: "https://example.com/updated",
              youtube_link: "https://youtube.example/updated"
            )
          },
          calls: []
        )

        freeze_time do
          client = FakeClient.new(
            model: "gpt-5-mini",
            responses: [
              {
                "output_text" => {
                  events: [
                    {
                      event_id: events(:published_one).id,
                      genre: [ "Indie", "Pop" ],
                      venue: "LKA Longhorn",
                      event_description: "Event eins",
                      venue_description: "Venue eins",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: "https://example.com/one-refresh",
                      facebook_link: nil
                    },
                    {
                      event_id: events(:needs_review_one).id,
                      genre: [ "Rock" ],
                      venue: "Im Wizemann",
                      event_description: "Event neu",
                      venue_description: "Venue neu",
                      youtube_link: "https://youtube.example/updated",
                      instagram_link: nil,
                      homepage_link: "https://example.com/updated",
                      facebook_link: nil
                    },
                    {
                      event_id: events(:needs_review_two).id,
                      genre: [ "Show" ],
                      venue: "Im Wizemann",
                      event_description: "Event drei",
                      venue_description: "Venue drei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    }
                  ]
                }.to_json
              }
            ]
          )

          result = build_importer(client: client, link_finder: link_finder).call

          assert_equal 3, result.selected_count
          assert_equal 0, result.skipped_count
          assert_equal 3, result.enriched_count
          assert_equal 1, result.batches_count

          updated_enrichment = events(:needs_review_one).reload.llm_enrichment
          assert_equal existing_enrichment.id, updated_enrichment.id
          assert_equal [ "Rock" ], updated_enrichment.genre
          assert_equal "Im Wizemann", updated_enrichment.venue
          assert_equal "Event neu", updated_enrichment.event_description
          assert_equal "https://example.com/updated", updated_enrichment.homepage_link
          assert_equal "gpt-5-mini", updated_enrichment.model
          assert_equal "v4", updated_enrichment.prompt_version
          assert_equal @run, updated_enrichment.source_run
        end
      end

      test "does not process past events even when they are missing an enrichment" do
        travel_to(Time.zone.parse("2026-06-15 12:00:00")) do
          client = FakeClient.new(
            model: "gpt-5-mini",
            responses: [
              {
                "output_text" => {
                  events: [
                    {
                      event_id: events(:needs_review_one).id,
                      genre: [ "Rock" ],
                      venue: "Im Wizemann",
                      event_description: "Event eins",
                      venue_description: "Venue eins",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    },
                    {
                      event_id: events(:needs_review_two).id,
                      genre: [ "Show" ],
                      venue: "Im Wizemann",
                      event_description: "Event zwei",
                      venue_description: "Venue zwei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    }
                  ]
                }.to_json
              }
            ]
          )

          result = build_importer(client: client).call

          assert_equal 2, result.selected_count
          assert_equal 0, result.skipped_count
          assert_equal 2, result.enriched_count
          assert_nil events(:published_one).reload.llm_enrichment
          assert_nil events(:published_past_one).reload.llm_enrichment
        end
      end

      test "refresh mode does not process past events" do
        @run.update!(metadata: @run.metadata.merge("refresh_existing" => true))

        travel_to(Time.zone.parse("2026-06-15 12:00:00")) do
          client = FakeClient.new(
            model: "gpt-5-mini",
            responses: [
              {
                "output_text" => {
                  events: [
                    {
                      event_id: events(:needs_review_one).id,
                      genre: [ "Rock" ],
                      venue: "Im Wizemann",
                      event_description: "Event eins",
                      venue_description: "Venue eins",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    },
                    {
                      event_id: events(:needs_review_two).id,
                      genre: [ "Show" ],
                      venue: "Im Wizemann",
                      event_description: "Event zwei",
                      venue_description: "Venue zwei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    }
                  ]
                }.to_json
              }
            ]
          )

          result = build_importer(client: client).call

          assert_equal 2, result.selected_count
          assert_equal 0, result.skipped_count
          assert_equal 2, result.enriched_count
          assert_nil events(:published_one).reload.llm_enrichment
          assert_nil events(:published_past_one).reload.llm_enrichment
        end
      end

      test "runs successfully with zero batches when no future events need enrichment" do
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

        freeze_time do
          client = FakeClient.new(model: "gpt-5-mini", responses: [])

          result = build_importer(client: client).call

          assert_equal 3, result.selected_count
          assert_equal 3, result.skipped_count
          assert_equal 0, result.enriched_count
          assert_equal 0, result.batches_count
          assert_nil result.merge_run_id
        end
      end

      test "runs successfully with zero batches when there are no future events" do
        travel_to(Time.zone.parse("2026-08-01 12:00:00")) do
          client = FakeClient.new(model: "gpt-5-mini", responses: [])

          result = build_importer(client: client).call

          assert_equal 0, result.selected_count
          assert_equal 0, result.skipped_count
          assert_equal 0, result.enriched_count
          assert_equal 0, result.batches_count
          assert_nil result.merge_run_id
        end
      end

      test "single event run overwrites an existing enrichment for a past event" do
        event = events(:published_past_one)
        existing_enrichment = EventLlmEnrichment.create!(
          event: event,
          source_run: import_runs(:one),
          genre: [ "Alt" ],
          venue: "Alte Venue",
          event_description: "Alt",
          venue_description: "Alt",
          youtube_link: nil,
          instagram_link: nil,
          homepage_link: nil,
          facebook_link: nil,
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
            {
              "output_text" => {
                events: [
                  {
                    event_id: event.id,
                    genre: [ "Jazz" ],
                    venue: "Neue Venue",
                    event_description: "Neu",
                    venue_description: "Neu",
                    youtube_link: nil,
                    instagram_link: nil,
                    homepage_link: "https://example.com/past",
                    facebook_link: nil
                  }
                ]
              }.to_json
            }
          ]
        )

        result = build_importer(
          client: client,
          link_finder: FakeLinkFinder.new(
            results_by_event_id: {
              event.id => fake_link_lookup_result(homepage_link: "https://example.com/past")
            },
            calls: []
          )
        ).call

        assert_equal 1, result.selected_count
        assert_equal 0, result.skipped_count
        assert_equal 1, result.enriched_count
        assert_equal 1, result.batches_count

        updated_enrichment = event.reload.llm_enrichment
        assert_equal existing_enrichment.id, updated_enrichment.id
        assert_equal [ "Jazz" ], updated_enrichment.genre
        assert_equal "Neue Venue", updated_enrichment.venue
        assert_equal "https://example.com/past", updated_enrichment.homepage_link
        assert_equal @run, updated_enrichment.source_run
      end

      test "single event run creates a new enrichment when none exists" do
        event = events(:published_past_one)
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
            {
              "output_text" => {
                events: [
                  {
                    event_id: event.id,
                    genre: [ "Jazz" ],
                    venue: "Jazzclub",
                    event_description: "Event",
                    venue_description: "Venue",
                    youtube_link: nil,
                    instagram_link: nil,
                    homepage_link: nil,
                    facebook_link: nil
                  }
                ]
              }.to_json
            }
          ]
        )

        result = build_importer(client: client).call

        assert_equal 1, result.selected_count
        assert_equal 0, result.skipped_count
        assert_equal 1, result.enriched_count
        assert_equal [ "Jazz" ], event.reload.llm_enrichment.genre
      end

      test "filters meta genres and stores rejected terms in raw_response" do
        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            {
              "output_text" => {
                events: [
                  {
                    event_id: events(:published_one).id,
                    genre: [ "Show", "Indie" ],
                    venue: "LKA Longhorn",
                    event_description: "Event eins",
                    venue_description: "Venue eins",
                    youtube_link: nil,
                    instagram_link: nil,
                    homepage_link: nil,
                    facebook_link: nil
                  },
                  {
                    event_id: events(:needs_review_one).id,
                    genre: [ "Concert", "Live Event", "Konzert", " Veranstaltungen " ],
                    venue: "Im Wizemann",
                    event_description: "Event zwei",
                    venue_description: "Venue zwei",
                    youtube_link: nil,
                    instagram_link: nil,
                    homepage_link: nil,
                    facebook_link: nil
                  },
                  {
                    event_id: events(:needs_review_two).id,
                    genre: [ "Comedy" ],
                    venue: "Im Wizemann",
                    event_description: "Event drei",
                    venue_description: "Venue drei",
                    youtube_link: nil,
                    instagram_link: nil,
                    homepage_link: nil,
                    facebook_link: nil
                  }
                ]
              }.to_json
            }
          ]
        )

        result = build_importer(client: client).call

        assert_equal 3, result.enriched_count

        first_enrichment = events(:published_one).reload.llm_enrichment
        assert_equal [ "Indie" ], first_enrichment.genre
        assert_equal [ "Show", "Indie" ], first_enrichment.raw_response.fetch("genre")
        assert_equal [ "Show" ], first_enrichment.raw_response.dig("genre_filter", "rejected_terms")
        assert_equal "v4", first_enrichment.prompt_version

        second_enrichment = events(:needs_review_one).reload.llm_enrichment
        assert_equal [], second_enrichment.genre
        assert_equal [ "Concert", "Live Event", "Konzert", " Veranstaltungen " ], second_enrichment.raw_response.fetch("genre")
        assert_equal [ "Concert", "Live Event", "Konzert", "Veranstaltungen" ],
          second_enrichment.raw_response.dig("genre_filter", "rejected_terms")

        assert_equal [ "Comedy" ], events(:needs_review_two).reload.llm_enrichment.genre
      end

      test "does not overwrite an existing venue from llm enrichment data" do
        event = events(:published_one)
        event.venue_record.update!(description: "Bestehende Venue-Beschreibung")

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            {
              "output_text" => {
                events: [
                  {
                    event_id: event.id,
                    genre: [ "Indie" ],
                    venue: "Komplett Andere Venue",
                    event_description: "Event",
                    venue_description: "Neue LLM Venue-Beschreibung",
                    youtube_link: nil,
                    instagram_link: nil,
                    homepage_link: nil,
                    facebook_link: nil
                  }
                ]
              }.to_json
            }
          ]
        )

        build_importer(client: client).call

        event.reload
        assert_equal "LKA Longhorn", event.venue
        assert_equal "Bestehende Venue-Beschreibung", event.venue_record.description
        assert_equal "Komplett Andere Venue", event.llm_enrichment.venue
        assert_equal "Neue LLM Venue-Beschreibung", event.llm_enrichment.venue_description
      end

      test "fills blank venue metadata from matching llm enrichment data without overwriting present values" do
        event = events(:published_one)
        event.venue_record.update!(
          description: nil,
          external_url: "https://bestehend.example",
          address: nil
        )

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            {
              "output_text" => {
                events: [
                  {
                    event_id: event.id,
                    genre: [ "Indie" ],
                    venue: "LKA Longhorn",
                    event_description: "Event",
                    venue_description: "Neue LLM Venue-Beschreibung",
                    venue_external_url: "https://neu.example",
                    venue_address: "Neue Adresse 7, Stuttgart",
                    youtube_link: nil,
                    instagram_link: nil,
                    homepage_link: nil,
                    facebook_link: nil
                  }
                ]
              }.to_json
            }
          ]
        )

        build_importer(client: client).call

        event.reload
        assert_equal "Neue LLM Venue-Beschreibung", event.venue_record.description
        assert_equal "https://bestehend.example", event.venue_record.external_url
        assert_equal "Neue Adresse 7, Stuttgart", event.venue_record.address
      end

      test "raises when openai response contains unexpected event ids" do
        freeze_time do
          client = FakeClient.new(
            model: "gpt-5-mini",
            responses: [
              {
                "output_text" => {
                  events: [
                    {
                      event_id: events(:published_past_one).id,
                      genre: [ "Jazz" ],
                      venue: "LKA Longhorn",
                      event_description: "Event",
                      venue_description: "Venue",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    }
                  ]
                }.to_json
              }
            ]
          )

          error = assert_raises(Importer::Error) do
            build_importer(client: client).call
          end

          assert_includes error.message, "nicht im aktuellen Batch"
        end
      end

      test "ignores duplicate event ids in the same response batch" do
        freeze_time do
          event = events(:published_one)
          link_finder = FakeLinkFinder.new(
            results_by_event_id: {
              event.id => fake_link_lookup_result(homepage_link: "https://example.com/first")
            },
            calls: []
          )

          client = FakeClient.new(
            model: "gpt-5-mini",
            responses: [
              {
                "output_text" => {
                  events: [
                    {
                      event_id: event.id,
                      genre: [ "Indie" ],
                      venue: "Erste Venue",
                      event_description: "Erste Event-Beschreibung",
                      venue_description: "Erste Venue-Beschreibung",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: "https://example.com/first",
                      facebook_link: nil
                    },
                    {
                      event_id: event.id,
                      genre: [ "Rock" ],
                      venue: "Zweite Venue",
                      event_description: "Zweite Event-Beschreibung",
                      venue_description: "Zweite Venue-Beschreibung",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: "https://example.com/second",
                      facebook_link: nil
                    },
                    {
                      event_id: events(:needs_review_one).id,
                      genre: [ "Pop" ],
                      venue: "Im Wizemann",
                      event_description: "Event zwei",
                      venue_description: "Venue zwei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    },
                    {
                      event_id: events(:needs_review_two).id,
                      genre: [ "Show" ],
                      venue: "Im Wizemann",
                      event_description: "Event drei",
                      venue_description: "Venue drei",
                      youtube_link: nil,
                      instagram_link: nil,
                      homepage_link: nil,
                      facebook_link: nil
                    }
                  ]
                }.to_json
              }
            ]
          )

          result = build_importer(client: client, link_finder: link_finder).call

          assert_equal 3, result.enriched_count

          enrichment = event.reload.llm_enrichment
          assert_equal [ "Indie" ], enrichment.genre
          assert_equal "Erste Venue", enrichment.venue
          assert_equal "https://example.com/first", enrichment.homepage_link
        end
      end

      test "refresh_links_only updates only existing link fields without calling OpenAI" do
        event = events(:published_one)
        enrichment = EventLlmEnrichment.create!(
          event: event,
          source_run: import_runs(:one),
          genre: [ "Indie" ],
          venue: "LKA Longhorn",
          event_description: "Bestehend",
          venue_description: "Venue",
          homepage_link: nil,
          youtube_link: nil,
          instagram_link: nil,
          facebook_link: nil,
          model: "existing-model",
          prompt_version: "v2",
          raw_response: { "event_id" => event.id }
        )
        @run.update!(
          metadata: @run.metadata.merge(
            "refresh_existing" => true,
            "refresh_links_only" => true,
            "target_event_ids" => [ event.id ]
          )
        )
        client = Struct.new(:model) do
          def create!(**)
            raise "OpenAI darf in refresh_links_only nicht aufgerufen werden"
          end
        end.new("gpt-5-mini")
        link_finder = FakeLinkFinder.new(
          results_by_event_id: {
            event.id => fake_link_lookup_result(
              homepage_link: "https://example.com/refreshed",
              instagram_link: "https://instagram.example/refreshed"
            )
          },
          calls: []
        )

        result = build_importer(client: client, link_finder: link_finder).call

        assert_equal 1, result.selected_count
        assert_equal 1, result.enriched_count
        assert_equal 2, result.links_found_via_web_search_count

        enrichment.reload
        assert_equal enrichment.id, event.reload.llm_enrichment.id
        assert_equal [ "Indie" ], enrichment.genre
        assert_equal "Bestehend", enrichment.event_description
        assert_equal "https://example.com/refreshed", enrichment.homepage_link
        assert_equal "https://instagram.example/refreshed", enrichment.instagram_link
        assert_equal "existing-model", enrichment.model
        assert_equal "v2", enrichment.prompt_version
        assert_equal "https://example.com/refreshed", enrichment.raw_response.dig("link_lookup", "fields", "homepage_link", "selected_url")
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
                events: [
                  {
                    event_id: @target_event_id,
                    genre: [ "Indie" ],
                    venue: "LKA Longhorn",
                    event_description: "Event eins",
                    venue_description: "Venue eins",
                    youtube_link: nil,
                    instagram_link: nil,
                    homepage_link: nil,
                    facebook_link: nil
                  }
                ]
              }.to_json
            }
          end
        end.new(@run, target_event_id)

        result = build_importer(client: client).call

        assert_equal true, result.canceled
        assert_equal 0, result.enriched_count
        assert_nil events(:published_one).reload.llm_enrichment
      end

      private

      def stub_const(constant_name, value)
        original = constant_name.constantize
        parent_name, const_name = constant_name.split("::")[0...-1].join("::"), constant_name.split("::").last
        parent = parent_name.constantize
        parent.send(:remove_const, const_name)
        parent.const_set(const_name, value)
        yield
      ensure
        parent.send(:remove_const, const_name) if parent.const_defined?(const_name, false)
        parent.const_set(const_name, original)
      end

      def build_importer(client:, link_validator: FakeLinkValidator.new({}), link_finder: FakeLinkFinder.new(results_by_event_id: {}, calls: []))
        Importer.new(run: @run, client: client, link_validator: link_validator, link_finder: link_finder)
      end

      def fake_link_lookup_result(homepage_link: nil, instagram_link: nil, facebook_link: nil, youtube_link: nil)
        links = {
          homepage_link: homepage_link,
          instagram_link: instagram_link,
          facebook_link: facebook_link,
          youtube_link: youtube_link
        }

        LinkFinder::Result.new(
          links: links,
          payload: {
            "queries" => [],
            "fields" => links.transform_keys(&:to_s).transform_values do |value|
              {
                "selected_url" => value,
                "candidates" => value.present? ? [ { "url" => value, "validation" => { "status" => "ok" } } ] : []
              }
            end
          },
          web_search_request_count: 0,
          web_search_candidate_count: links.values.compact.size,
          links_found_via_web_search_count: links.values.count(&:present?),
          links_null_after_link_lookup_count: links.values.count(&:blank?),
          validation_results: []
        )
      end
    end
  end
end
