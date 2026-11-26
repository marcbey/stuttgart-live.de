require "test_helper"

class AnonymousSentryEventTest < ActiveSupport::TestCase
  test "the export constructs a fresh error event from technical values only" do
    configuration = Sentry::Configuration.new
    configuration.environment = "production"
    configuration.release = "a" * 40
    configuration.server_name = "patient@example.invalid"
    configuration.rails.structured_logging.enabled = true
    original = Sentry::ErrorEvent.new(configuration:, message: "patient@example.invalid")
    original.user = { email: "patient@example.invalid", ip_address: "192.0.2.80" }
    original.tags = { request_id: "unique-request-id" }
    original.extra = { url: "/login?email=patient@example.invalid" }
    original.contexts = { trace: { trace_id: "unique-trace-id" } }
    original.attachments = [ "private attachment" ]
    error = ArgumentError.new("patient@example.invalid")
    error.set_backtrace([ "#{Rails.root}/app/controllers/sessions_controller.rb:42:in 'create'" ])
    original.add_exception_interface(error, mechanism: Sentry::Mechanism.new)

    AnonymousSentryEvent.configure(configuration)
    forwarded = configuration.before_send.call(original, {})

    assert_equal "ArgumentError (app/controllers/sessions_controller.rb:42)", forwarded.message
    assert_equal "a" * 40, forwarded.release
    assert_equal "production", forwarded.environment
    assert_not_equal original.event_id, forwarded.event_id
    assert_empty forwarded.attachments
    assert_nil forwarded.dynamic_sampling_context
    %w[patient@example.invalid 192.0.2.80 unique-request-id unique-trace-id].each do |value|
      assert_not_includes forwarded.to_json_compatible.to_json, value
    end
    assert_not configuration.rails.structured_logging.enabled
    assert_not configuration.propagate_traces
    assert_nil configuration.traces_sample_rate
  end
end
