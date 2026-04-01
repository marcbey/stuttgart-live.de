# frozen_string_literal: true

# config/initializers/sentry.rb
require "active_support/parameter_filter"

Sentry.init do |config|
  config.dsn = Rails.application.credentials.dig(:sentry, :dsn)

  config.enabled_environments = %w[production]
  config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)
  config.release = ENV["SENTRY_RELEASE"]

  config.breadcrumbs_logger = %i[active_support_logger http_logger]

  # Am Anfang lieber konservativ
  config.send_default_pii = false
  config.enable_logs = true
  config.traces_sample_rate = 0.1
  config.profiles_sample_rate = 0.0

  filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

  config.before_send = lambda do |event, _hint|
    event.extra    = filter.filter(event.extra)    if event.extra
    event.user     = filter.filter(event.user)     if event.user
    event.contexts = filter.filter(event.contexts) if event.contexts
    event
  end
end
