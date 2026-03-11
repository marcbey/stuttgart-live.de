require "test_helper"
require "rake"

class BlogImportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("blog:import_wordpress_news")
    Rake::Task["blog:import_wordpress_news"].reenable
  end

  test "task uses default author deterministically without arguments" do
    called_author = nil
    result = Blog::WordpressImporter::Result.new(created_count: 0, updated_count: 0, errors: [])
    default_author = users(:two)

    importer_singleton = class << Blog::WordpressImporter
      self
    end

    original_call = Blog::WordpressImporter.method(:call)
    original_default_author = Blog::WordpressImporter.method(:default_author)

    importer_singleton.define_method(:default_author) do
      default_author
    end

    importer_singleton.define_method(:call) do |author:|
      called_author = author
      result
    end

    begin
      output = capture_io do
        Rake::Task["blog:import_wordpress_news"].invoke
      end.first

      assert_includes output, "Autor: #{default_author.email_address}"
    ensure
      importer_singleton.define_method(:default_author, original_default_author)
      importer_singleton.define_method(:call, original_call)
    end

    assert_equal default_author, called_author
  end
end
