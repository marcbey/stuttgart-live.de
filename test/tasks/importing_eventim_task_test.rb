require "test_helper"
require "rake"

class ImportingEventimTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("importing:eventim:repair_ticket_offers")
    Rake::Task["importing:eventim:repair_ticket_offers"].reenable
  end

  test "repair_ticket_offers delegates to repairer" do
    captured_kwargs = nil
    result = Events::Maintenance::EventimTicketOfferRepairer::Result.new(
      checked_events: 2,
      updated_events: 1,
      created_offers: 0,
      removed_stale_offers: 1,
      ignored_auxiliary_records: 0,
      ambiguous_events: 0,
      dry_run: true,
      series_summaries: {
        "Eventim Repair Series" => {
          "checked_events" => 2,
          "updated_events" => 1,
          "created_offers" => 0,
          "removed_stale_offers" => 1,
          "ignored_auxiliary_records" => 0,
          "ambiguous_events" => 0
        }
      }
    )
    original_dry_run = ENV["DRY_RUN"]
    original_call = Events::Maintenance::EventimTicketOfferRepairer.method(:call)
    ENV["DRY_RUN"] = "1"

    Events::Maintenance::EventimTicketOfferRepairer.singleton_class.define_method(:call) do |**kwargs|
      captured_kwargs = kwargs
      result
    end

    output = capture_io do
      Rake::Task["importing:eventim:repair_ticket_offers"].invoke
    end.first

    assert_equal({ dry_run: true }, captured_kwargs)
    assert_includes output, "Eventim Ticket-Angebote geprüft."
    assert_includes output, "checked_events=2"
    assert_includes output, "updated_events=1"
    assert_includes output, "series=Eventim Repair Series checked_events=2 updated_events=1 removed_stale_offers=1 ambiguous_events=0"
  ensure
    ENV["DRY_RUN"] = original_dry_run
    Events::Maintenance::EventimTicketOfferRepairer.singleton_class.define_method(:call, original_call)
  end
end
