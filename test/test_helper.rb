ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

if defined?(Bullet)
  module BulletRequestLifecycle
    def before_setup
      super
      Bullet.start_request if bullet_enabled?
    end

    def after_teardown
      if bullet_enabled?
        Bullet.perform_out_of_channel_notifications if Bullet.notification?
        Bullet.end_request
      end

      super
    end

    private

    def bullet_enabled?
      Bullet.respond_to?(:enable?) ? Bullet.enable? : Bullet.enable
    end
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

if defined?(Bullet)
  ActiveSupport::TestCase.prepend(BulletRequestLifecycle)
end
