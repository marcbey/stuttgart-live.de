require "test_helper"

class NewsletterSubscriberTest < ActiveSupport::TestCase
  test "normalizes email before validation" do
    subscriber = NewsletterSubscriber.create!(email: "  TEST@Example.com  ", source: "homepage")

    assert_equal "test@example.com", subscriber.email
  end

  test "rejects duplicate emails case-insensitively" do
    NewsletterSubscriber.create!(email: "hello@example.com", source: "homepage")
    duplicate = NewsletterSubscriber.new(email: "HELLO@example.com", source: "homepage")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end
end
