require "test_helper"

class Backend::SettingsGenreCountsTest < ActionDispatch::IntegrationTest
  setup do
    EventGenre.delete_all
    AppSetting.where(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY).delete_all
    AppSetting.create!(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY, value: [ genres(:pop).slug, genres(:rock).slug ])
    AppSetting.reset_cache!
    sign_in_as(users(:two))
  end

  teardown { AppSetting.reset_cache! }

  test "genre settings count upcoming public events in one query" do
    create_event("shared", genres: [ genres(:rock), genres(:pop) ])
    create_event("rock", genres: [ genres(:rock) ])
    create_event("past", genres: [ genres(:pop) ], start_at: 2.days.ago)
    create_event("draft", genres: [ genres(:pop) ], status: "needs_review")
    create_event("scheduled", genres: [ genres(:pop) ], published_at: 1.day.from_now)

    queries = []
    callback = ->(event) { queries << event.payload[:sql].to_s }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get edit_backend_settings_url(section: :homepage_genre_lanes)
    end

    assert_response :success
    assert_equal 1, queries.grep(/SELECT COUNT\(.*FROM "events"/m).size

    rows = Nokogiri::HTML(response.body).css(".settings-reference-item")
    counts = rows.to_h do |row|
      [ row.at_css("input[type='checkbox']")["value"], row.at_css(".settings-reference-checkbox-copy span").text ]
    end
    assert_equal "2 kommende Events", counts.fetch("rock-alternative")
    assert_equal "1 kommende Events", counts.fetch("pop-indie-singer-songwriter")
    assert_equal "0 kommende Events", counts.fetch("jazz-blues-soul")
    assert_equal [ "pop-indie-singer-songwriter", "rock-alternative" ], counts.keys.first(2)
  end

  private

  def create_event(key, genres:, start_at: 3.days.from_now, status: "published", published_at: 1.day.ago)
    Event.create!(
      source_fingerprint: "test::settings-genre-counts::#{key}",
      artist_name: "Settings Artist #{key}",
      title: "Settings Programme #{key}",
      start_at:,
      venue: "Test Venue",
      city: "Stuttgart",
      status:,
      published_at:,
      genres:
    )
  end
end
