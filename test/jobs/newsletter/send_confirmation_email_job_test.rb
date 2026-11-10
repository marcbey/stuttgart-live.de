require "test_helper"
require "faraday/adapter/test"

class Newsletter::SendConfirmationEmailJobTest < ActiveJob::TestCase
  test "retries a confirmation rejected by the daily quota and delivers once capacity returns" do
    subscriber = sign_up
    responses = [ daily_quota_rejection, accepted_delivery ]

    assert_enqueued_with(job: Newsletter::SendConfirmationEmailJob, args: [ subscriber ])

    freeze_time do
      with_mailjet(responses) do
        perform_enqueued_jobs(at: Time.current)

        assert_enqueued_jobs 1, only: Newsletter::SendConfirmationEmailJob
        retry_window = 1.day.from_now..27.hours.from_now
        assert_enqueued_with(job: Newsletter::SendConfirmationEmailJob, args: [ subscriber ],
                             at: ->(time) { retry_window.cover?(time) })

        travel 27.hours
        perform_enqueued_jobs(at: Time.current)
      end
    end

    assert_empty responses
    assert_no_enqueued_jobs
    assert_not subscriber.reload.confirmed?
  end

  test "does not send a queued confirmation for an older signup" do
    responses = [ accepted_delivery ]

    freeze_time do
      subscriber = sign_up
      assert subscriber.request_signup(newsletter_consent: "1")

      with_mailjet(responses) { perform_enqueued_jobs }
    end

    assert_empty responses
  end

  test "does not retry a legacy job once a newer signup has been made" do
    subscriber = sign_up
    clear_enqueued_jobs
    legacy_job = Newsletter::SendConfirmationEmailJob.new(subscriber).serialize.except("signup_digest")
    responses = [ daily_quota_rejection, accepted_delivery ]

    freeze_time do
      with_mailjet(responses) do
        ActiveJob::Base.execute(legacy_job)
        assert subscriber.request_signup(newsletter_consent: "1")
        perform_enqueued_jobs(at: Time.current)

        travel 27.hours
        perform_enqueued_jobs(at: Time.current)
      end
    end

    assert_empty responses
    assert_no_enqueued_jobs
  end

  test "does not send a legacy job first executed after a newer signup" do
    responses = [ accepted_delivery ]

    freeze_time do
      subscriber = sign_up
      clear_enqueued_jobs
      legacy_job = Newsletter::SendConfirmationEmailJob.new(subscriber).serialize.except("signup_digest")

      travel 1.minute
      assert subscriber.request_signup(newsletter_consent: "1")

      with_mailjet(responses) do
        ActiveJob::Base.execute(legacy_job)
        perform_enqueued_jobs
      end
    end

    assert_empty responses
  end

  test "surfaces a persistent daily quota rejection after two retries" do
    sign_up
    responses = Array.new(3) { daily_quota_rejection }

    with_mailjet(responses) do
      perform_enqueued_jobs
      perform_enqueued_jobs
      assert_raises(Newsletter::MailjetClient::Error) { perform_enqueued_jobs }
    end

    assert_empty responses
    assert_no_enqueued_jobs
  end

  test "does not retry a per-second mailjet rate limit on the daily schedule" do
    sign_up
    responses = [ mailjet_response(429, "ErrorMessage" => "Too many requests") ]

    with_mailjet(responses) do
      assert_raises(Newsletter::MailjetClient::Error) { perform_enqueued_jobs }
    end

    assert_empty responses
    assert_no_enqueued_jobs
  end

  private

  def sign_up
    NewsletterSubscriber.new(email: "confirm@example.com").tap do |subscriber|
      assert subscriber.request_signup(newsletter_consent: "1")
    end
  end

  def accepted_delivery
    mailjet_response(200, "Messages" => [ { "Status" => "success" } ])
  end

  def daily_quota_rejection
    mailjet_response(429, "ErrorMessage" => "Daily sending limit was exceeded")
  end

  def mailjet_response(status, body)
    [ status, { "Content-Type" => "application/json" }, body.to_json ]
  end

  def with_mailjet(responses)
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/v3/REST/sender") { mailjet_response(200, "Data" => []) }
      stub.post("/v3.1/send") { responses.shift || flunk("Unexpected confirmation email") }
    end
    original_client = Newsletter::MailjetClient.method(:new)
    original_connection = Mailjet::Connection.method(:new)
    Newsletter::MailjetClient.define_singleton_method(:new) do
      original_client.call(api_key: "test-key", secret_key: "test-secret")
    end
    Mailjet::Connection.define_singleton_method(:new) do |*arguments|
      connection = original_connection.call(*arguments)
      connection.adapter = Faraday.new(connection.uri) do |http|
        http.response :raise_error
        http.adapter :test, stubs
      end
      connection
    end
    yield
  ensure
    Newsletter::MailjetClient.define_singleton_method(:new, original_client)
    Mailjet::Connection.define_singleton_method(:new, original_connection)
  end
end
