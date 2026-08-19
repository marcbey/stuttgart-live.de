module Newsletter
  class SyncInterestToMailjet
    def self.call(interest, client: MailjetClient.new)
      new(interest, client:).call
    end

    def initialize(interest, client: MailjetClient.new)
      @interest = interest
      @client = client
    end

    def call
      return interest.mailjet_segment_id if interest.blank? || interest.mailjet_segment_id.present?

      client.ensure_contact_property(name: interest.mailjet_property_name, data_type: "bool")
      response = client.create_contact_segment(
        name: segment_name,
        expression: "(#{interest.mailjet_property_name}=true)",
        description: "Stuttgart Live Newsletter Interesse: #{interest.name}"
      )
      interest.update!(mailjet_segment_id: response.fetch("ID"))
      interest.mailjet_segment_id
    end

    private

    attr_reader :interest, :client

    def segment_name
      "stuttgart_live_newsletter_#{interest.slug.tr("-", "_")}"
    end
  end
end
