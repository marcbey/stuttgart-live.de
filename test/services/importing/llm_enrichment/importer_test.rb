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
        @merge_run = @source.import_runs.create!(
          source_type: "merge",
          status: "succeeded",
          started_at: 5.minutes.ago,
          finished_at: 4.minutes.ago,
          metadata: {}
        )
        @run = @source.import_runs.create!(
          source_type: "llm_enrichment",
          status: "running",
          started_at: 1.minute.ago,
          metadata: {}
        )
      end

      test "selects merged create and update events from latest successful merge and persists enrichments" do
        create_change_log!(events(:needs_review_one), merge_run_id: @merge_run.id, action: "merged_create")
        create_change_log!(events(:needs_review_two), merge_run_id: @merge_run.id, action: "merged_create")

        older_merge_run = @source.import_runs.create!(
          source_type: "merge",
          status: "succeeded",
          started_at: 20.minutes.ago,
          finished_at: 19.minutes.ago,
          metadata: {}
        )
        create_change_log!(events(:published_one), merge_run_id: older_merge_run.id, action: "merged_create")
        create_change_log!(events(:published_past_one), merge_run_id: @merge_run.id, action: "merged_update")

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            {
              "output_text" => {
                events: [
                  {
                    event_id: events(:needs_review_one).id,
                    genre: [ "Indie", "Pop" ],
                    venue: "Im Wizemann",
                    artist_description: "Artist eins",
                    event_description: "Event eins",
                    venue_description: "Venue eins",
                    youtube_link: "https://youtube.example/one",
                    instagram_link: "https://instagram.example/one",
                    homepage_link: "https://example.com/one",
                    facebook_link: "https://facebook.example/one"
                  },
                  {
                    event_id: events(:needs_review_two).id,
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
                    event_id: events(:published_past_one).id,
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
        assert_equal @merge_run.id, result.merge_run_id

        enrichment = events(:needs_review_one).reload.llm_enrichment
        assert_equal [ "Indie", "Pop" ], enrichment.genre
        assert_equal "https://example.com/one", enrichment.homepage_link
        assert_equal @run, enrichment.source_run

        assert_nil events(:published_one).reload.llm_enrichment
        assert_equal [ "Show" ], events(:published_past_one).reload.llm_enrichment.genre
      end

      test "skips events that already have an enrichment and batches remaining events" do
        create_change_log!(events(:needs_review_one), merge_run_id: @merge_run.id, action: "merged_create")
        create_change_log!(events(:needs_review_two), merge_run_id: @merge_run.id, action: "merged_create")

        EventLlmEnrichment.create!(
          event: events(:needs_review_one),
          source_run: import_runs(:one),
          genre: [ "Pop" ],
          model: "existing-model",
          prompt_version: "v1",
          raw_response: { "event_id" => events(:needs_review_one).id }
        )

        stub_const("#{Importer}::BATCH_SIZE", 1) do
          client = FakeClient.new(
            model: "gpt-5-mini",
            responses: [
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

          assert_equal 2, result.selected_count
          assert_equal 1, result.skipped_count
          assert_equal 1, result.enriched_count
          assert_equal 1, result.batches_count
        end
      end

      test "raises when openai response contains unexpected event ids" do
        create_change_log!(events(:needs_review_one), merge_run_id: @merge_run.id, action: "merged_create")

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            {
              "output_text" => {
                events: [
                  {
                    event_id: events(:published_one).id,
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

      private

      def create_change_log!(event, merge_run_id:, action:)
        EventChangeLog.create!(
          event: event,
          action: action,
          changed_fields: {},
          metadata: { merge_run_id: merge_run_id }
        )
      end

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
