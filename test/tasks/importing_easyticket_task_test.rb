require "test_helper"
require "rake"

class ImportingEasyticketTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("importing:easyticket:repair_ticket_urls")
    Rake::Task["importing:easyticket:repair_ticket_urls"].reenable
  end

  test "repair_ticket_urls delegates to repairer" do
    captured_kwargs = nil
    result = Events::Maintenance::EasyticketTicketUrlRepairer::Result.new(
      checked_count: 2,
      updated_count: 1,
      unchanged_count: 1,
      missing_raw_import_count: 0,
      blank_expected_url_count: 0,
      dry_run: true
    )
    original_dry_run = ENV["DRY_RUN"]
    original_call = Events::Maintenance::EasyticketTicketUrlRepairer.method(:call)
    ENV["DRY_RUN"] = "1"

    Events::Maintenance::EasyticketTicketUrlRepairer.singleton_class.define_method(:call) do |**kwargs|
      captured_kwargs = kwargs
      result
    end

    output = capture_io do
      Rake::Task["importing:easyticket:repair_ticket_urls"].invoke
    end.first

    assert_equal({ dry_run: true }, captured_kwargs)
    assert_includes output, "Easyticket Ticket-URLs geprüft."
    assert_includes output, "checked=2"
    assert_includes output, "updated=1"
  ensure
    ENV["DRY_RUN"] = original_dry_run
    Events::Maintenance::EasyticketTicketUrlRepairer.singleton_class.define_method(:call, original_call)
  end
end
