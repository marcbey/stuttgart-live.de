require "test_helper"

class ExternalActionPolicyTest < ActiveSupport::TestCase
  setup { assert defined?(ExternalActionPolicy), "External action policy is required" }

  test "only runtime production and isolated development tests may call external integrations" do
    %i[mailjet meta external_import paid_ai].each do |action|
      %w[production development test].each do |environment|
        assert ExternalActionPolicy.require_allowed!(action:, environment:)
      end
      %w[staging build unknown].each do |environment|
        assert_raises(ExternalActionPolicy::Disabled) { ExternalActionPolicy.require_allowed!(action:, environment:) }
      end
    end
    assert_raises(ArgumentError) { ExternalActionPolicy.require_allowed!(action: :misspelled, environment: "production") }
  end

  test "real clients block staging before SDK and HTTP calls even with injected credentials" do
    with_staging do
      with_test_method(Mailjet, :configure, ->(*) { flunk "Mailjet SDK must not be configured" }) do
        client = Newsletter::MailjetClient.new(api_key: "real-looking-key", secret_key: "real-looking-secret", list_id: "123")
        error = assert_raises(Newsletter::MailjetClient::Error) { client.subscribe(email: "person@example.invalid") }
        assert_includes error.message, "Staging"
      end
      with_test_method(Net::HTTP, :start, ->(*) { flunk "No external HTTP connection may be opened" }) do
        assert_raises(Meta::Error) { Meta::HttpClient.new.get_json!("https://graph.facebook.com/me", params: { access_token: "real-looking-token" }) }
        assert_raises(Meta::Error) { Meta::HttpClient.new.post_form!("https://graph.facebook.com/me", params: { access_token: "real-looking-token" }) }
        [ Importing::Eventim::HttpClient, Importing::Easyticket::HttpClient, Importing::Reservix::HttpClient ].each do |klass|
          assert_raises(ExternalActionPolicy::Disabled) { klass.new.get("https://tickets.example.invalid/feed") }
        end
        [ Importing::LlmEnrichment::SerpApiClient, Importing::LlmEnrichment::OpenWebNinjaWebSearchClient ].each do |klass|
          assert_raises(ExternalActionPolicy::Disabled) { klass.new(api_key: "real-looking-key").search(query: "test") }
        end
        client = OpenAi::ResponsesClient.new(model: "test-model", sdk_client: Object.new)
        error = assert_raises(OpenAi::ResponsesClient::Error) { client.create!(input: "test", text_format: {}) }
        assert_includes error.message, "Staging"
      end
    end
  end

  test "newsletter confirmation mail uses local mail delivery without consulting an injected API client" do
    with_staging do
      client = Object.new
      def client.api_configured? = raise("Injected client must not be consulted")
      subscriber = NewsletterSubscriber.create!(email: "person@example.invalid", source: "homepage")
      mail = NewsletterMailer.confirmation(subscriber)
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        Newsletter::DeliverEmail.call(mail, client:)
      end
    end
  end

  test "public tracking is absent in staging even when the request host is a production host" do
    with_staging do
      helper = ApplicationController.helpers
      request = Struct.new(:host).new("stuttgart-live.de")
      with_test_method(helper, :request, -> { request }) do
        assert_nil helper.google_analytics_measurement_id
        assert_nil helper.meta_pixel_id
      end
    end
  end

  test "Sentry reports staging even with a conflicting inherited environment" do
    with_staging do
      previous = ENV["SENTRY_ENVIRONMENT"]
      ENV["SENTRY_ENVIRONMENT"] = "production"
      config = Sentry::Configuration.new
      with_test_method(Sentry, :init, ->(&block) { block.call(config) }) do
        load Rails.root.join("config/initializers/sentry.rb")
      end
      assert_equal "staging", config.environment
      assert_includes config.enabled_environments, "staging"
    ensure
      previous.nil? ? ENV.delete("SENTRY_ENVIRONMENT") : ENV["SENTRY_ENVIRONMENT"] = previous
    end
  end

  test "recurring scheduler is absent while local workers remain configured" do
    Tempfile.create([ "recurring-test", ".yml" ]) do |file|
      file.write({ Rails.env => { "test_task" => { "command" => "raise 'must never execute'", "schedule" => "every hour" } } }.to_yaml)
      file.flush
      previous = ENV["SOLID_QUEUE_SKIP_RECURRING"]
      ENV["SOLID_QUEUE_SKIP_RECURRING"] = "true"
      config = SolidQueue::Configuration.new(recurring_schedule_file: Pathname.new(file.path))
      kinds = config.configured_processes.map(&:kind)
      assert_includes kinds, :worker
      refute_includes kinds, :scheduler
    ensure
      previous.nil? ? ENV.delete("SOLID_QUEUE_SKIP_RECURRING") : ENV["SOLID_QUEUE_SKIP_RECURRING"] = previous
    end
  end

  test "manual import attempts cannot bypass the client policy" do
    with_staging do
      # DNS resolution itself is an external action and must not run first.
      fetcher = LegacyRedirects::HttpFetcher.new(dns: ->(*) { flunk "No DNS lookup in staging" })
      assert_raises(ExternalActionPolicy::Disabled) { fetcher.call("https://stuttgart-live.de/old") }
    end
  end

  test "manually performed newsletter sync remains blocked with a fully configured real client" do
    subscriber = NewsletterSubscriber.create!(email: "manual@example.invalid", confirmed_at: Time.current)
    client = Newsletter::MailjetClient.new(api_key: "real-looking-key", secret_key: "real-looking-secret", list_id: "123")
    with_staging do
      with_test_method(Newsletter::MailjetClient, :new, ->(**) { client }) do
        with_test_method(Mailjet, :configure, ->(*) { flunk "No SDK calls from manual jobs" }) do
          assert_raises(Newsletter::MailjetClient::Error) { Newsletter::SyncSubscriberJob.new.perform(subscriber) }
        end
      end
      assert_equal NewsletterSubscriber::EXTERNAL_SYNC_STATUS_FAILED, subscriber.reload.external_sync_status
      assert_includes subscriber.external_error_message, "Staging"
    end
  end

  test "newsletter external send controls stay disabled in staging despite enabled credentials" do
    with_staging do
      with_test_method(AppConfig, :fetch, ->(*, **) { "true" }) do
        refute AppConfig.newsletter_final_send_enabled?
        refute AppConfig.newsletter_test_list_send_enabled?
      end
    end
  end

  test "Meta OAuth cannot redirect staging users to an external consent page" do
    with_staging do
      [ Meta::Onboarding::AuthorizationUrlBuilder, Meta::Onboarding::InstagramAuthorizationUrlBuilder ].each do |builder|
        session = {}
        error = assert_raises(Meta::Error) { builder.new(app_id: "real-looking-id").call(session:, redirect_uri: "https://stuttgart-live.de/callback") }
        assert_includes error.message, "Staging"
        assert_empty session
      end
    end
  end

  private

  def with_test_method(target, name, implementation)
    original = target.method(name) if target.respond_to?(name, true)
    target.define_singleton_method(name, implementation)
    yield
  ensure
    target.singleton_class.remove_method(name)
    target.define_singleton_method(name, original) if original
  end

  def with_staging
    original = Rails.configuration.x.deployment_environment
    Rails.configuration.x.deployment_environment = "staging"
    yield
  ensure
    Rails.configuration.x.deployment_environment = original
  end
end
