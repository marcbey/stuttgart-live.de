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

    importer_singleton = class << Blog::WordpressImporter
      self
    end

    original_call = Blog::WordpressImporter.method(:call)

    importer_singleton.define_method(:call) do |author:|
      called_author = author
      result
    end

    begin
      output = capture_io do
        Rake::Task["blog:import_wordpress_news"].invoke("blogger@example.com")
      end.first

      assert_includes output, "Autor: blogger@example.com"
    ensure
      importer_singleton.define_method(:call, original_call)
    end

    assert_equal users(:blogger), called_author
  end
end
