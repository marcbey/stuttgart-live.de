require "test_helper"
require "rake"

class BlogImportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("blog:import_wordpress_news")
    Rake::Task["blog:import_wordpress_news"].reenable
  end

  test "task resolves explicit author email deterministically" do
    called_author = nil
    result = Blog::WordpressImporter::Result.new(created_count: 0, updated_count: 0, errors: [])

    Blog::WordpressImporter.stub(:call, ->(author:) {
      called_author = author
      result
    }) do
      output = capture_io do
        Rake::Task["blog:import_wordpress_news"].invoke("blogger@example.com")
      end.first

      assert_includes output, "Autor: blogger@example.com"
    end

    assert_equal users(:blogger), called_author
  end
end
