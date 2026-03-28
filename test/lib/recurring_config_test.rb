require "test_helper"

class RecurringConfigTest < ActiveSupport::TestCase
  test "production recurring config includes event retention jobs" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    production = config.fetch("production")

    assert_equal(
      "Events::Retention::PruneStaleUnpublishedEventsJob.perform_later",
      production.fetch("daily_event_retention_cleanup").fetch("command")
    )
    assert_equal(
      "every day at 6:05am",
      production.fetch("daily_event_retention_cleanup").fetch("schedule")
    )
    assert_equal(
      "Events::Retention::PrunePastRawEventImportsJob.perform_later",
      production.fetch("daily_raw_event_import_retention_cleanup").fetch("command")
    )
    assert_equal(
      "every day at 6:35am",
      production.fetch("daily_raw_event_import_retention_cleanup").fetch("schedule")
    )
  end
end
