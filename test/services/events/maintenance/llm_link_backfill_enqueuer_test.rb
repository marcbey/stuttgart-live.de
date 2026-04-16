require "test_helper"

module Events
  module Maintenance
    class LlmLinkBackfillEnqueuerTest < ActiveSupport::TestCase
      FakeRegistry = Struct.new(:import_source) do
        def resolve_run_source(_source_type)
          import_source
        end
      end

      FakeRunEnqueuer = Struct.new(:calls) do
        def call(**kwargs)
          calls << kwargs
        end
      end

      test "enqueues future enriched events in chunks with refresh_links_only metadata" do
        now = Time.zone.parse("2026-04-16 10:00:00")
        source = import_sources(:two)

        published_event = events(:published_one)
        published_event.update!(status: "published", start_at: now + 2.days)
        published_event.llm_enrichment || EventLlmEnrichment.create!(
          event: published_event,
          source_run: import_runs(:one),
          model: "existing-model",
          prompt_version: "v1",
          raw_response: {}
        )

        review_event = events(:needs_review_one)
        review_event.update!(status: "needs_review", start_at: now + 3.days)
        review_event.llm_enrichment || EventLlmEnrichment.create!(
          event: review_event,
          source_run: import_runs(:one),
          model: "existing-model",
          prompt_version: "v1",
          raw_response: {}
        )

        queued_calls = []
        result = LlmLinkBackfillEnqueuer.new(
          chunk_size: 1,
          statuses: %w[published needs_review],
          clock: -> { now },
          importer_registry: FakeRegistry.new(source),
          run_enqueuer: FakeRunEnqueuer.new(queued_calls)
        ).call

        assert_equal 2, result.eligible_count
        assert_equal 2, result.runs_enqueued
        assert_equal [ published_event.id ], queued_calls.first.dig(:run_metadata, "target_event_ids")
        assert_equal true, ActiveModel::Type::Boolean.new.cast(queued_calls.first.dig(:run_metadata, "refresh_links_only"))
      end
    end
  end
end
