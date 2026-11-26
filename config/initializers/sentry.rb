# frozen_string_literal: true

require_relative "../../app/lib/anonymous_sentry_event"

profile = Rails.configuration.x.deployment_environment
sentry_environment = profile == "staging" ? "staging" : ENV.fetch("SENTRY_ENVIRONMENT", profile)
disabled_sentry_environments = %w[test development build].freeze

unless disabled_sentry_environments.include?(sentry_environment)
  Sentry.init do |config|
    config.dsn = Rails.application.credentials.dig(:sentry, :dsn)

    config.enabled_environments = %w[production staging]
    config.environment = sentry_environment
    config.release = ENV["SENTRY_RELEASE"]

    AnonymousSentryEvent.configure(config)
  end
end
