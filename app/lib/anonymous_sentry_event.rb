# frozen_string_literal: true

module AnonymousSentryEvent
  ERROR_TYPES = %w[
    ActiveRecord::RecordInvalid ActiveRecord::RecordNotFound ArgumentError
    LoadError NameError NoMethodError PG::ConnectionBad RuntimeError TypeError
  ].freeze
  APP_SOURCE = %r{\Aapp/[a-z0-9_/]+\.rb\z}

  def self.configure(configuration)
    configuration.send_default_pii = false
    configuration.send_modules = false
    configuration.send_client_reports = false
    configuration.auto_session_tracking = false
    configuration.propagate_traces = false
    configuration.rails.structured_logging.enabled = false
    configuration.before_send = ->(event, _hint) { build(event, configuration:) }
    configuration.before_send_transaction = ->(_event, _hint) { nil }
    configuration.before_send_check_in = ->(_event, _hint) { nil }
  end

  def self.build(event, configuration:)
    error = event.exception&.values&.last
    type = ERROR_TYPES.include?(error&.type) ? error.type : "ApplicationError"
    location = app_location(error)
    summary = location ? "#{type} (#{location})" : type

    Sentry::ErrorEvent.new(configuration:, message: summary).tap do |anonymous|
      anonymous.level = :error
      anonymous.server_name = nil
      anonymous.environment = nil unless %w[production staging].include?(anonymous.environment)
      anonymous.release = nil unless anonymous.release&.match?(/\A[a-f0-9]{40}\z/)
      anonymous.fingerprint = [ type, location ].compact
    end
  end
  private_class_method :build

  def self.app_location(error)
    error&.stacktrace&.frames&.reverse_each do |frame|
      path = frame.abs_path.to_s.delete_prefix("#{Rails.root}/")
      next unless APP_SOURCE.match?(path) && File.file?(Rails.root.join(path))
      next unless frame.lineno.is_a?(Integer) && frame.lineno.positive?

      return "#{path}:#{frame.lineno}"
    end
    nil
  end
  private_class_method :app_location
end
