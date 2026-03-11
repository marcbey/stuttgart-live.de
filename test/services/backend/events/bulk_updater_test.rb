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
    assert @event.published_at.present?
    assert_equal "bulk_publish", @event.event_change_logs.order(:created_at, :id).last.action
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
end
