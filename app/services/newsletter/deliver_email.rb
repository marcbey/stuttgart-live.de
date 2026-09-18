module Newsletter
  class DeliverEmail
    def self.call(mail, client: MailjetClient.new)
      return mail.deliver_now unless client.api_configured?

      client.send_transactional_email(
        to: mail.to.first, subject: mail.subject,
        html: mail.html_part.body.decoded, text: mail.text_part.body.decoded
      )
    end
  end
end
