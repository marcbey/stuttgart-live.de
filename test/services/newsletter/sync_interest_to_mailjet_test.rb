require "test_helper"

class Newsletter::SyncInterestToMailjetTest < ActiveSupport::TestCase
  test "creates property and segment when interest has no segment id" do
    interest = newsletter_interests(:pop)
    interest.update!(mailjet_segment_id: nil)
    client = RecordingClient.new

    assert_equal 4242, Newsletter::SyncInterestToMailjet.call(interest, client:)

    assert_equal 4242, interest.reload.mailjet_segment_id
    assert_equal [ :ensure_contact_property, :create_contact_segment ], client.calls.map(&:first)
  end

  test "keeps existing segment id" do
    interest = newsletter_interests(:rock)
    client = RecordingClient.new

    assert_equal 1002, Newsletter::SyncInterestToMailjet.call(interest, client:)
    assert_empty client.calls
  end

  RecordingClient = Struct.new(:calls) do
    def initialize
      super([])
    end

    def ensure_contact_property(name:, data_type:)
      calls << [ :ensure_contact_property, name, data_type ]
      { "ID" => 3131 }
    end

    def create_contact_segment(name:, expression:, description:)
      calls << [ :create_contact_segment, name, expression, description ]
      { "ID" => 4242 }
    end
  end
end
