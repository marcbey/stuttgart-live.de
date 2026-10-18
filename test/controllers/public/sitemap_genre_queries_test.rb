require "test_helper"

class Public::SitemapGenreQueriesTest < ActionDispatch::IntegrationTest
  test "sitemap batches genre route checks while excluding conflicting paths" do
    EventGenre.delete_all
    genres(:metal).update!(slug: "highlights")
    StaticPage.create!(slug: genres(:pop).slug, title: "Genre landing page", body: "<div>Informationen</div>")
    Event.create!(
      source_fingerprint: "test::sitemap-genre-queries",
      artist_name: "Sitemap Artist",
      title: "Sitemap Programme",
      start_at: 2.days.from_now,
      venue: "Test Venue",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      genres: [ genres(:rock), genres(:pop), genres(:metal), genres(:jazz) ]
    )

    queries = []
    callback = ->(event) { queries << event.payload[:sql].to_s }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get sitemap_url(format: :xml) }

    assert_response :success
    assert_equal 1, queries.grep(/SELECT "genres"\."slug" FROM/).size
    assert_equal 1, queries.grep(/SELECT "static_pages"\."slug" FROM/).size

    document = Nokogiri::XML(response.body)
    document.remove_namespaces!
    genre_locs = document.css("url").filter_map do |entry|
      entry.at_css("loc").text if entry.at_css("priority").text == "0.7"
    end
    assert_equal [ "#{root_url}jazz-blues-soul", "#{root_url}rock-alternative" ], genre_locs
    assert_includes document.css("loc").map(&:text), static_page_url(genres(:pop).slug)
  end
end
