require "test_helper"

class Public::Events::HomepageGenreTagCloudBuilderTest < ActiveSupport::TestCase
  setup do
    EventGenre.delete_all
    AppSetting.where(key: AppSetting::HOMEPAGE_GENRE_TAG_CLOUD_ENABLED_KEY).delete_all
    AppSetting.where(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY).delete_all
    AppSetting.create!(key: AppSetting::HOMEPAGE_GENRE_TAG_CLOUD_ENABLED_KEY, value: true)
    AppSetting.create!(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY, value: [])
    AppSetting.reset_cache!

    @rock_group = genres(:rock)
    @pop_group = genres(:pop)
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "resolves tag public paths in bulk" do
    rock_event = build_event(slug: "tag-cloud-bulk-rock", artist_name: "Tag Cloud Rock")
    pop_event = build_event(slug: "tag-cloud-bulk-pop", artist_name: "Tag Cloud Pop")
    rock_event.genres = [ @rock_group ]
    pop_event.genres = [ @pop_group ]

    queries = capture_sql_queries do
      tags = Public::Events::HomepageGenreTagCloudBuilder.new(
        relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
      ).call

      assert_includes tags.map(&:slug), @rock_group.slug
      assert_includes tags.map(&:slug), @pop_group.slug
    end

    single_slug_queries = queries.grep(/"genres"\."slug" =/)
    static_page_slug_queries = queries.grep(/"static_pages"\."slug" =/)

    assert_empty single_slug_queries
    assert_empty static_page_slug_queries
  end

  private

  def build_event(slug:, artist_name:)
    Event.create!(
      slug: slug,
      source_fingerprint: "test::service::homepage-genre-tag-cloud::#{slug}",
      title: "#{artist_name} Title",
      artist_name: artist_name,
      start_at: 10.days.from_now.change(hour: 20),
      venue: "Club Zentral",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
  end

  def capture_sql_queries
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if payload[:cached]
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries
  end
end
