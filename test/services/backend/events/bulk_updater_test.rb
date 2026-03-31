require "test_helper"

class Backend::Events::BulkUpdaterTest < ActiveSupport::TestCase
  setup do
    @event = events(:needs_review_one)
    @user = users(:one)
  end

  test "publishes events and records change logs" do
    processed = Backend::Events::BulkUpdater.new(
      events: Event.where(id: @event.id),
      action: "publish",
      user: @user
    ).call

    assert_equal 1, processed
    assert_equal "published", @event.reload.status
    assert_nil @event.published_at
    assert_equal "bulk_publish", @event.event_change_logs.order(:created_at, :id).last.action
  end

  test "bulk publish rejects an explicitly scheduled publication time" do
    scheduled_time = 3.days.from_now.change(usec: 0)
    @event.update!(published_at: scheduled_time)

    assert_raises(ActiveRecord::RecordInvalid) do
      Backend::Events::BulkUpdater.new(
        events: Event.where(id: @event.id),
        action: "publish",
        user: @user
      ).call
    end

    assert_equal "needs_review", @event.reload.status
    assert_equal scheduled_time, @event.published_at
  end

  test "rejects events" do
    processed = Backend::Events::BulkUpdater.new(
      events: Event.where(id: @event.id),
      action: "reject",
      user: @user
    ).call

    assert_equal 1, processed
    assert_equal "rejected", @event.reload.status
  end

  test "groups selected events into a manual event series" do
    second_event = events(:needs_review_two)

    processed = Backend::Events::BulkUpdater.new(
      events: Event.where(id: [ @event.id, second_event.id ]),
      action: "group_as_series",
      user: @user
    ).call

    assert_equal 2, processed
    assert @event.reload.event_series.manual?
    assert_equal @event.event_series_id, second_event.reload.event_series_id
    assert_equal "manual", @event.event_series_assignment
    assert_equal "bulk_group_as_series", @event.event_change_logs.order(:created_at, :id).last.action
  end

  test "removes selected events from their event series" do
    series = EventSeries.create!(origin: "manual", name: "Bulk Reihe")
    @event.update!(event_series: series, event_series_assignment: "manual")

    processed = Backend::Events::BulkUpdater.new(
      events: Event.where(id: @event.id),
      action: "remove_from_series",
      user: @user
    ).call

    assert_equal 1, processed
    assert_nil @event.reload.event_series_id
    assert_equal "manual_none", @event.event_series_assignment
    assert_nil EventSeries.find_by(id: series.id)
    assert_equal "bulk_remove_from_series", @event.event_change_logs.order(:created_at, :id).last.action
  end
end
