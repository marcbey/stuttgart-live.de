class NewsletterMailer < ApplicationMailer
  def confirmation(subscriber)
    @subscriber = subscriber
    @confirmation_url = newsletter_confirmation_url(subscriber.confirmation_token)

    mail subject: "Bitte bestätige deine Newsletter-Anmeldung", to: subscriber.email
  end
end
