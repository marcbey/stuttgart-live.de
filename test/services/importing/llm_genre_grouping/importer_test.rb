require "test_helper"

module Importing
  module LlmGenreGrouping
    class ImporterTest < ActiveSupport::TestCase
      FakeClient = Struct.new(:responses, :model, :calls, keyword_init: true) do
        def create!(input:, text_format:)
          raise "missing input" if input.blank?
          raise "missing schema" if text_format.blank?

          self.calls ||= []
          calls << { input:, text_format: }

          response = responses.shift || raise("no fake response left")
          raise response if response.is_a?(Exception)

          response
        end
      end

      setup do
        AppSetting.where(key: AppSetting::LLM_GENRE_GROUPING_MODEL_KEY).delete_all
        AppSetting.where(key: AppSetting::LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY).delete_all
        AppSetting.where(key: AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_KEY).delete_all
        AppSetting.reset_cache!

        AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_MODEL_KEY, value: "gpt-5-mini")
        AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY, value: "Gruppiere {{group_count}}\n{{input_json}}")
        AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_KEY, value: 3)

        @run = ImportRun.create!(
          import_source: import_sources(:two),
          source_type: "llm_genre_grouping",
          status: "running",
          started_at: 1.minute.ago,
          metadata: {}
        )
      end

      teardown do
        AppSetting.reset_cache!
      end

      test "groups normalized distinct genres and persists an active snapshot" do
        EventLlmEnrichment.create!(
          event: events(:published_one),
          source_run: import_runs(:one),
          genre: [ " Rock ", "Pop" ],
          model: "gpt-5-mini",
          prompt_version: "v1",
          raw_response: {}
        )
        EventLlmEnrichment.create!(
          event: events(:needs_review_one),
          source_run: import_runs(:one),
          genre: [ "Indie", "Pop" ],
          model: "gpt-5-mini",
          prompt_version: "v1",
          raw_response: {}
        )
        old_snapshot = ImportRun.create!(
          import_source: import_sources(:one),
          source_type: "llm_genre_grouping",
          status: "succeeded",
          started_at: 2.minutes.ago,
          finished_at: 1.minute.ago
        ).create_llm_genre_grouping_snapshot!(
          active: true,
          requested_group_count: 2,
          effective_group_count: 2,
          source_genres_count: 2,
          model: "gpt-5-mini",
          prompt_template_digest: "old",
          request_payload: {},
          raw_response: {}
        )

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            {
              "output_text" => {
                groups: [
                  { position: 1, name: "Rock & Pop", genres: [ "Rock", "Pop" ] },
                  { position: 2, name: "Indie", genres: [ "Indie" ] },
                  { position: 3, name: "Sonstiges", genres: [ "Jazz" ] }
                ]
              }.to_json
            }
          ]
        )

        EventLlmEnrichment.create!(
          event: events(:needs_review_two),
          source_run: import_runs(:one),
          genre: [ "Jazz" ],
          model: "gpt-5-mini",
          prompt_version: "v1",
          raw_response: {}
        )

        result = Importer.new(run: @run, client: client).call

        assert_equal 4, result.selected_count
        assert_equal 0, result.skipped_count
        assert_equal 3, result.groups_count
        assert_equal 1, result.requests_count

        snapshot = @run.reload.llm_genre_grouping_snapshot
        assert snapshot.present?
        assert_equal true, snapshot.active
        assert_equal false, old_snapshot.reload.active
        assert_equal 3, snapshot.groups.count
        assert_equal [ "Rock", "Pop" ].sort, snapshot.groups.find_by!(position: 1).member_genres.sort
      end

      test "uses fallback chunking and consolidation when single request is too large" do
        fallback_events = Array.new(4) { |index| create_grouping_event!(suffix: "fallback-error-#{index}") }

        %w[Rock Pop Indie Jazz].each_with_index do |genre, index|
          EventLlmEnrichment.create!(
            event: fallback_events[index],
            source_run: import_runs(:one),
            genre: [ genre ],
            model: "gpt-5-mini",
            prompt_version: "v1",
            raw_response: {}
          )
        end

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            { "output_text" => { groups: [ { position: 1, name: "Indie", genres: [ "Indie" ] }, { position: 2, name: "Jazz", genres: [ "Jazz" ] } ] }.to_json },
            { "output_text" => { groups: [ { position: 1, name: "Pop", genres: [ "Pop" ] }, { position: 2, name: "Rock", genres: [ "Rock" ] } ] }.to_json },
            { "output_text" => { groups: [ { position: 1, name: "Rock & Pop", provisional_group_ids: [ 3, 4 ] }, { position: 2, name: "Indie & Jazz", provisional_group_ids: [ 1, 2 ] }, { position: 3, name: "Mix", provisional_group_ids: [] } ] }.to_json }
          ]
        )

        with_stubbed_importer_constants(
          max_single_call_input_json_bytes: 1,
          fallback_chunk_size: 2,
          invalid_response_max_attempts: 1,
          repair_invalid_response_max_attempts: 0
        ) do
          error = assert_raises(Importer::Error) do
            Importer.new(run: @run, client: client).call
          end

          assert_includes error.message, "leere Gruppe"
        end
      end

      test "fallback chunking succeeds with consolidation" do
        fallback_events = Array.new(4) { |index| create_grouping_event!(suffix: "fallback-success-#{index}") }

        %w[Rock Pop Indie Jazz].each_with_index do |genre, index|
          EventLlmEnrichment.create!(
            event: fallback_events[index],
            source_run: import_runs(:one),
            genre: [ genre ],
            model: "gpt-5-mini",
            prompt_version: "v1",
            raw_response: {}
          )
        end

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            { "output_text" => { groups: [ { position: 1, name: "Indie", genres: [ "Indie" ] }, { position: 2, name: "Jazz", genres: [ "Jazz" ] } ] }.to_json },
            { "output_text" => { groups: [ { position: 1, name: "Pop", genres: [ "Pop" ] }, { position: 2, name: "Rock", genres: [ "Rock" ] } ] }.to_json },
            { "output_text" => { groups: [ { position: 1, name: "Rock & Pop", provisional_group_ids: [ 3, 4 ] }, { position: 2, name: "Indie", provisional_group_ids: [ 1 ] }, { position: 3, name: "Jazz", provisional_group_ids: [ 2 ] } ] }.to_json }
          ]
        )

        result = nil
        with_stubbed_importer_constants(max_single_call_input_json_bytes: 1, fallback_chunk_size: 2) do
          result = Importer.new(run: @run, client: client).call
        end

        assert_equal 3, result.groups_count
        assert_equal 3, result.requests_count
        assert_equal "fallback", @run.reload.llm_genre_grouping_snapshot.request_payload["mode"]
      end

      test "uses fallback chunking when genre count exceeds threshold" do
        fallback_events = Array.new(4) { |index| create_grouping_event!(suffix: "fallback-threshold-#{index}") }

        %w[Rock Pop Indie Jazz].each_with_index do |genre, index|
          EventLlmEnrichment.create!(
            event: fallback_events[index],
            source_run: import_runs(:one),
            genre: [ genre ],
            model: "gpt-5-mini",
            prompt_version: "v1",
            raw_response: {}
          )
        end

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            { "output_text" => { groups: [ { position: 1, name: "Indie", genres: [ "Indie" ] }, { position: 2, name: "Jazz", genres: [ "Jazz" ] } ] }.to_json },
            { "output_text" => { groups: [ { position: 1, name: "Pop", genres: [ "Pop" ] }, { position: 2, name: "Rock", genres: [ "Rock" ] } ] }.to_json },
            { "output_text" => { groups: [ { position: 1, name: "Rock & Pop", provisional_group_ids: [ 3, 4 ] }, { position: 2, name: "Indie", provisional_group_ids: [ 1 ] }, { position: 3, name: "Jazz", provisional_group_ids: [ 2 ] } ] }.to_json }
          ]
        )

        result = with_stubbed_importer_constants(
          max_single_call_genre_count: 3,
          max_single_call_input_json_bytes: 999_999,
          fallback_chunk_size: 2
        ) do
          Importer.new(run: @run, client: client).call
        end

        assert_equal 3, result.requests_count
        assert_equal "fallback", @run.reload.llm_genre_grouping_snapshot.request_payload["mode"]
        assert_equal "genre_count_too_large", @run.reload.llm_genre_grouping_snapshot.request_payload["fallback_reason"]
      end

      test "retries incomplete grouping response and succeeds on corrected retry" do
        EventLlmEnrichment.create!(
          event: events(:published_one),
          source_run: import_runs(:one),
          genre: [ "Rock", "Pop", "Jazz" ],
          model: "gpt-5-mini",
          prompt_version: "v1",
          raw_response: {}
        )

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            {
              "output_text" => {
                groups: [
                  { position: 1, name: "Rock", genres: [ "Rock" ] },
                  { position: 2, name: "Leer", genres: [] },
                  { position: 3, name: "Jazz", genres: [ "Jazz" ] }
                ]
              }.to_json
            },
            {
              "output_text" => {
                groups: [
                  { position: 1, name: "Rock", genres: [ "Rock" ] },
                  { position: 2, name: "Pop", genres: [ "Pop" ] },
                  { position: 3, name: "Jazz", genres: [ "Jazz" ] }
                ]
              }.to_json
            }
          ]
        )

        result = with_stubbed_importer_constants(
          max_single_call_input_json_bytes: 100,
          fallback_chunk_size: 2,
          invalid_response_max_attempts: 2
        ) do
          Importer.new(run: @run, client: client).call
        end

        assert_equal 3, result.selected_count
        assert_equal 3, result.groups_count
        assert_equal 2, result.requests_count
        assert_equal 2, client.calls.size
        assert_includes client.calls.second.fetch(:input), "Der letzte Versuch war ungültig"

        snapshot = @run.reload.llm_genre_grouping_snapshot
        assert_equal 2, snapshot.request_payload.dig("requests", 0, "attempt_count")
        assert_equal 2, snapshot.raw_response.dig("responses", 0, "attempt_count")
      end

      test "repairs incomplete grouping after normal retries are exhausted" do
        EventLlmEnrichment.create!(
          event: events(:published_one),
          source_run: import_runs(:one),
          genre: [ "Rock", "Pop", "Jazz" ],
          model: "gpt-5-mini",
          prompt_version: "v1",
          raw_response: {}
        )

        incomplete_response = {
          "output_text" => {
            groups: [
              { position: 1, name: "Rock", genres: [ "Rock" ] },
              { position: 2, name: "Leer", genres: [] },
              { position: 3, name: "Jazz", genres: [ "Jazz" ] }
            ]
          }.to_json
        }

        fixed_response = {
          "output_text" => {
            groups: [
              { position: 1, name: "Rock", genres: [ "Rock" ] },
              { position: 2, name: "Pop", genres: [ "Pop" ] },
              { position: 3, name: "Jazz", genres: [ "Jazz" ] }
            ]
          }.to_json
        }

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [ incomplete_response, fixed_response ]
        )

        result = with_stubbed_importer_constants(
          max_single_call_input_json_bytes: 100,
          fallback_chunk_size: 2,
          invalid_response_max_attempts: 1,
          repair_invalid_response_max_attempts: 1
        ) do
          Importer.new(run: @run, client: client).call
        end

        assert_equal 2, result.requests_count
        assert_equal 2, client.calls.size
        assert_includes client.calls.second.fetch(:input), "Korrigiere die fehlerhafte Genre-Gruppierung"

        snapshot = @run.reload.llm_genre_grouping_snapshot
        assert_equal "repair", snapshot.request_payload.dig("requests", 0, "attempts", 1, "stage")
        assert_equal "repair", snapshot.raw_response.dig("responses", 0, "attempts", 1, "stage")
      end

      test "heuristically repairs incomplete chunk grouping after retries and repair are exhausted" do
        fallback_events = Array.new(4) { |index| create_grouping_event!(suffix: "heuristic-chunk-#{index}") }

        %w[Rock Pop Indie Jazz].each_with_index do |genre, index|
          EventLlmEnrichment.create!(
            event: fallback_events[index],
            source_run: import_runs(:one),
            genre: [ genre ],
            model: "gpt-5-mini",
            prompt_version: "v1",
            raw_response: {}
          )
        end

        client = FakeClient.new(
          model: "gpt-5-mini",
          responses: [
            { "output_text" => { groups: [ { position: 1, name: "Rock", genres: [ "Rock" ] }, { position: 2, name: "Leer", genres: [] } ] }.to_json },
            { "output_text" => { groups: [ { position: 1, name: "Indie", genres: [ "Indie" ] }, { position: 2, name: "Jazz", genres: [ "Jazz" ] } ] }.to_json },
            { "output_text" => { groups: [ { position: 1, name: "Rock & Pop", provisional_group_ids: [ 1, 2 ] }, { position: 2, name: "Indie", provisional_group_ids: [ 3 ] }, { position: 3, name: "Jazz", provisional_group_ids: [ 4 ] } ] }.to_json }
          ]
        )

        result = with_stubbed_importer_constants(
          max_single_call_input_json_bytes: 1,
          fallback_chunk_size: 2,
          invalid_response_max_attempts: 1,
          repair_invalid_response_max_attempts: 0
        ) do
          Importer.new(run: @run, client: client).call
        end

        assert_equal 3, result.groups_count
        assert_equal 3, result.requests_count

        snapshot = @run.reload.llm_genre_grouping_snapshot
        assert_equal "heuristic_repair", snapshot.request_payload.dig("requests", 0, "attempts", 1, "stage")
        assert_equal %w[Indie Jazz Pop Rock], snapshot.groups.flat_map(&:member_genres).sort
      end

      test "returns canceled result when stop was requested before processing" do
        EventLlmEnrichment.create!(
          event: events(:published_one),
          source_run: import_runs(:one),
          genre: [ "Rock" ],
          model: "gpt-5-mini",
          prompt_version: "v1",
          raw_response: {}
        )
        @run.update!(metadata: { "stop_requested" => true })

        result = Importer.new(run: @run, client: FakeClient.new(model: "gpt-5-mini", responses: [])).call

        assert_equal true, result.canceled
        assert_equal 1, result.selected_count
        assert_nil result.snapshot_id
      end

      test "returns canceled result when stop was requested after a response" do
        EventLlmEnrichment.create!(
          event: events(:published_one),
          source_run: import_runs(:one),
          genre: [ "Rock" ],
          model: "gpt-5-mini",
          prompt_version: "v1",
          raw_response: {}
        )

        client = Class.new do
          attr_reader :model

          def initialize(run)
            @run = run
            @model = "gpt-5-mini"
          end

          def create!(input:, text_format:)
            raise "missing input" if input.blank?
            raise "missing schema" if text_format.blank?

            @run.update!(metadata: @run.metadata.merge("stop_requested" => true, "stop_requested_at" => Time.current.iso8601))
            { "output_text" => { groups: [ { position: 1, name: "Rock", genres: [ "Rock" ] } ] }.to_json }
          end
        end.new(@run)

        result = Importer.new(run: @run, client: client).call

        assert_equal true, result.canceled
        assert_equal 1, result.requests_count
        assert_nil result.snapshot_id
      end

      test "succeeds without snapshot when no genres exist" do
        result = Importer.new(run: @run, client: FakeClient.new(model: "gpt-5-mini", responses: [])).call

        assert_equal 0, result.selected_count
        assert_equal 0, result.groups_count
        assert_nil @run.reload.llm_genre_grouping_snapshot
      end

      private

      def create_grouping_event!(suffix:)
        Event.create!(
          slug: "llm-grouping-#{suffix}",
          title: "LLM Grouping #{suffix}",
          artist_name: "Artist #{suffix}",
          normalized_artist_name: "artist #{suffix}",
          start_at: 1.day.from_now,
          venue: "LKA Longhorn",
          status: "published"
        )
      end

      def with_stubbed_importer_constants(
        max_single_call_genre_count: Importer::MAX_SINGLE_CALL_GENRE_COUNT,
        max_single_call_input_json_bytes:,
        fallback_chunk_size:,
        invalid_response_max_attempts: Importer::INVALID_RESPONSE_MAX_ATTEMPTS,
        repair_invalid_response_max_attempts: Importer::REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS
      )
        original_count = Importer::MAX_SINGLE_CALL_GENRE_COUNT
        original_max = Importer::MAX_SINGLE_CALL_INPUT_JSON_BYTES
        original_chunk_size = Importer::FALLBACK_CHUNK_SIZE
        original_retry_attempts = Importer::INVALID_RESPONSE_MAX_ATTEMPTS
        original_repair_attempts = Importer::REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS

        Importer.send(:remove_const, :MAX_SINGLE_CALL_GENRE_COUNT)
        Importer.const_set(:MAX_SINGLE_CALL_GENRE_COUNT, max_single_call_genre_count)
        Importer.send(:remove_const, :MAX_SINGLE_CALL_INPUT_JSON_BYTES)
        Importer.const_set(:MAX_SINGLE_CALL_INPUT_JSON_BYTES, max_single_call_input_json_bytes)
        Importer.send(:remove_const, :FALLBACK_CHUNK_SIZE)
        Importer.const_set(:FALLBACK_CHUNK_SIZE, fallback_chunk_size)
        Importer.send(:remove_const, :INVALID_RESPONSE_MAX_ATTEMPTS)
        Importer.const_set(:INVALID_RESPONSE_MAX_ATTEMPTS, invalid_response_max_attempts)
        Importer.send(:remove_const, :REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS)
        Importer.const_set(:REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS, repair_invalid_response_max_attempts)

        yield
      ensure
        Importer.send(:remove_const, :MAX_SINGLE_CALL_GENRE_COUNT)
        Importer.const_set(:MAX_SINGLE_CALL_GENRE_COUNT, original_count)
        Importer.send(:remove_const, :MAX_SINGLE_CALL_INPUT_JSON_BYTES)
        Importer.const_set(:MAX_SINGLE_CALL_INPUT_JSON_BYTES, original_max)
        Importer.send(:remove_const, :FALLBACK_CHUNK_SIZE)
        Importer.const_set(:FALLBACK_CHUNK_SIZE, original_chunk_size)
        Importer.send(:remove_const, :INVALID_RESPONSE_MAX_ATTEMPTS)
        Importer.const_set(:INVALID_RESPONSE_MAX_ATTEMPTS, original_retry_attempts)
        Importer.send(:remove_const, :REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS)
        Importer.const_set(:REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS, original_repair_attempts)
      end
    end
  end
end
