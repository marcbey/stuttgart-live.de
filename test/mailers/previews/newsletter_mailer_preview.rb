class NewsletterMailerPreview < ActionMailer::Preview
  def confirmation
    subscriber = NewsletterSubscriber.first ||
      NewsletterSubscriber.create!(email: "newsletter-preview@example.com", source: "preview")

    NewsletterMailer.confirmation(subscriber)
  end
end
