require "test_helper"
require "rake"

class VenuesMaintenanceTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("venues:maintenance:backfill_duplicates")
    Rake::Task["venues:maintenance:backfill_duplicates"].reenable
  end

  test "backfill_duplicates delegates to the venues deduplicator" do
    result = Venues::Maintenance::Deduplicator::Result.new(
      groups: 2,
      venues_merged: 3,
      events_reassigned: 7,
      venues_deleted: 3
    )
    original_call = Venues::Maintenance::Deduplicator.method(:call)
    called = false

    Venues::Maintenance::Deduplicator.singleton_class.define_method(:call) do
      called = true
      result
    end

    output = capture_io do
      Rake::Task["venues:maintenance:backfill_duplicates"].invoke
    end.first

    assert called
    assert_includes output, "Venue-Dubletten bereinigt."
    assert_includes output, "groups=2"
    assert_includes output, "venues_merged=3"
    assert_includes output, "events_reassigned=7"
    assert_includes output, "venues_deleted=3"
  ensure
    Venues::Maintenance::Deduplicator.singleton_class.define_method(:call, original_call)
  end
end
