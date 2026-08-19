require "test_helper"

class Newsletter::SendConfirmationEmailTest < ActiveSupport::TestCase
  test "sends rendered confirmation email through mailjet client when configured" do
    subscriber = NewsletterSubscriber.create!(email: "confirm-api@example.com", source: "homepage")
    client = Client.new

    Newsletter::SendConfirmationEmail.call(subscriber, client:)

    assert_equal "confirm-api@example.com", client.delivery.fetch(:to)
    assert_equal "Bitte bestätige deine Newsletter-Anmeldung", client.delivery.fetch(:subject)
    assert_includes client.delivery.fetch(:html), "/newsletter/confirm/"
    assert_includes client.delivery.fetch(:text), "/newsletter/confirm/"
  end

  private

  class Client
    attr_reader :delivery

    def api_configured?
      true
    end

    def send_transactional_email(**delivery)
      @delivery = delivery
    end
  end
end
