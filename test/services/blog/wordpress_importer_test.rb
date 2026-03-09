require "test_helper"

class Blog::WordpressImporterTest < ActiveSupport::TestCase
  test "default_author picks the lowest id admin deterministically" do
    admin = users(:two)
    later_admin = User.create!(
      email_address: "later-admin@example.com",
      password: "password",
      password_confirmation: "password",
      role: "admin",
      name: "Later Admin"
    )

    assert_equal admin, Blog::WordpressImporter.default_author
    assert_operator admin.id, :<, later_admin.id
  end

  test "posts are sorted deterministically by published time and id" do
    importer = Blog::WordpressImporter.new(author: users(:two), logger: Logger.new(nil))
    unsorted_posts = [
      { "id" => 20, "date_gmt" => "2026-03-02T10:00:00", "date" => "2026-03-02T11:00:00+01:00" },
      { "id" => 10, "date_gmt" => "2026-03-01T10:00:00", "date" => "2026-03-01T11:00:00+01:00" },
      { "id" => 11, "date_gmt" => "2026-03-01T10:00:00", "date" => "2026-03-01T11:00:00+01:00" }
    ]

    importer.define_singleton_method(:source_posts) { unsorted_posts }

    assert_equal [ 10, 11, 20 ], importer.send(:posts).map { |payload| payload.fetch("id") }
  end
end
