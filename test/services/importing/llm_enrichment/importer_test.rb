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

      setup do
        @source = import_sources(:two)
        @run = @source.import_runs.create!(
          source_type: "llm_enrichment",
          status: "running",
          started_at: 1.minute.ago,
          metadata: {}
        )
      end

      test "selects all future events without enrichment and persists enrichments" do
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
                      artist_description: "Artist eins",
                      event_description: "Event eins",
                      venue_description: "Venue eins",
                      youtube_link: "https://youtube.example/one",
                      instagram_link: "https://instagram.example/one",
                      homepage_link: "https://example.com/one",
                      facebook_link: "https://facebook.example/one"
                    },
                    {
                      event_id: events(:needs_review_one).id,
                      genre: [ "Rock" ],
                      venue: "Im Wizemann",
                      artist_description: "Artist zwei",
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
                      artist_description: "Artist drei",
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

          result = Importer.new(run: @run, client: client).call

          assert_equal 3, result.selected_count
          assert_equal 0, result.skipped_count
          assert_equal 3, result.enriched_count
          assert_equal 1, result.batches_count
          assert_nil result.merge_run_id

          enrichment = events(:published_one).reload.llm_enrichment
          assert_equal [ "Indie", "Pop" ], enrichment.genre
          assert_equal "https://example.com/one", enrichment.homepage_link
          assert_equal @run, enrichment.source_run

          assert_equal [ "Rock" ], events(:needs_review_one).reload.llm_enrichment.genre
          assert_equal [ "Show" ], events(:needs_review_two).reload.llm_enrichment.genre
          assert_nil events(:published_past_one).reload.llm_enrichment
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
                        artist_description: "Artist eins",
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
                        artist_description: "Artist zwei",
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

            result = Importer.new(run: @run, client: client).call

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
          artist_description: "Alt",
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
                      artist_description: "Artist eins",
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
                      artist_description: "Artist neu",
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
                      artist_description: "Artist drei",
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

          result = Importer.new(run: @run, client: client).call

          assert_equal 3, result.selected_count
          assert_equal 0, result.skipped_count
          assert_equal 3, result.enriched_count
          assert_equal 1, result.batches_count

          updated_enrichment = events(:needs_review_one).reload.llm_enrichment
          assert_equal existing_enrichment.id, updated_enrichment.id
          assert_equal [ "Rock" ], updated_enrichment.genre
          assert_equal "Im Wizemann", updated_enrichment.venue
          assert_equal "Artist neu", updated_enrichment.artist_description
          assert_equal "https://example.com/updated", updated_enrichment.homepage_link
          assert_equal "gpt-5-mini", updated_enrichment.model
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
                      artist_description: "Artist eins",
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
                      artist_description: "Artist zwei",
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

          result = Importer.new(run: @run, client: client).call

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
                      artist_description: "Artist eins",
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
                      artist_description: "Artist zwei",
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

          result = Importer.new(run: @run, client: client).call

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

          result = Importer.new(run: @run, client: client).call

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

          result = Importer.new(run: @run, client: client).call

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
          artist_description: "Alt",
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
                    artist_description: "Neu",
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

        result = Importer.new(run: @run, client: client).call

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
                    artist_description: "Artist",
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

        result = Importer.new(run: @run, client: client).call

        assert_equal 1, result.selected_count
        assert_equal 0, result.skipped_count
        assert_equal 1, result.enriched_count
        assert_equal [ "Jazz" ], event.reload.llm_enrichment.genre
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
                      artist_description: "Artist",
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
            Importer.new(run: @run, client: client).call
          end

          assert_includes error.message, "nicht im aktuellen Batch"
        end
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
                    artist_description: "Artist eins",
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

        result = Importer.new(run: @run, client: client).call

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
    end
  end
end
