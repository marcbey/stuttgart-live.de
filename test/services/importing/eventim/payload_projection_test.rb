require "test_helper"

module Importing
  module Eventim
    class PayloadProjectionTest < ActiveSupport::TestCase
      test "maps core attributes from flexible payload keys" do
        projection = PayloadProjection.new(
          feed_payload: {
            "eventId" => "evt-77",
            "startDateTime" => "2026-11-03T20:00:00+01:00",
            "city" => "Stuttgart",
            "venueName" => "Im Wizemann",
            "eventTitle" => "Band C Live",
            "performer" => "Band C",
            "promoterId" => "36",
            "ticketUrl" => "https://tickets.example/evt-77",
            "imageUrl" => "https://img.example/evt-77.jpg"
          }
        )

        attributes = projection.to_attributes

        assert_equal "evt-77", attributes[:external_event_id]
        assert_equal Date.new(2026, 11, 3), attributes[:concert_date]
        assert_equal "3.11.2026", attributes[:concert_date_label]
        assert_equal "Stuttgart, Im Wizemann", attributes[:venue_label]
        assert_equal "Band C", attributes[:artist_name]
        assert_equal "36", attributes[:promoter_id]
        assert_equal "https://tickets.example/evt-77", attributes[:ticket_url]

        image_candidates = projection.image_candidates
        assert_equal 1, image_candidates.size
        assert_equal "image_url", image_candidates.first[:image_type]
        assert_equal "https://img.example/evt-77.jpg", image_candidates.first[:image_url]
      end

      test "maps attributes from eventim feed keys" do
        projection = PayloadProjection.new(
          feed_payload: {
            "eventid" => "20259466",
            "eventdate" => "2026-03-04",
            "eventplace" => "Stuttgart",
            "eventvenue" => "Im Wizemann",
            "eventname" => "Das Phantom der Oper",
            "sideArtistNames" => "Original Cast",
            "promoterid" => "10135",
            "eventlink" => "https://www.eventim.de/noapp/event/20259466/"
          }
        )

        attributes = projection.to_attributes

        assert_equal "20259466", attributes[:external_event_id]
        assert_equal Date.new(2026, 3, 4), attributes[:concert_date]
        assert_equal "4.3.2026", attributes[:concert_date_label]
        assert_equal "Stuttgart", attributes[:city]
        assert_equal "Im Wizemann", attributes[:venue_name]
        assert_equal "Das Phantom der Oper", attributes[:title]
        assert_equal "Original Cast", attributes[:artist_name]
        assert_equal "10135", attributes[:promoter_id]
        assert_equal "Stuttgart, Im Wizemann", attributes[:venue_label]
        assert_equal "https://www.eventim.de/noapp/event/20259466/", attributes[:ticket_url]
      end

      test "keeps city blank when no city key is present" do
        projection = PayloadProjection.new(
          feed_payload: {
            "eventid" => "20259466",
            "eventdate" => "2026-03-04",
            "eventvenue" => "Im Wizemann",
            "eventname" => "Das Phantom der Oper"
          }
        )

        attributes = projection.to_attributes

        assert_nil attributes[:city]
      end
    end
  end
end
