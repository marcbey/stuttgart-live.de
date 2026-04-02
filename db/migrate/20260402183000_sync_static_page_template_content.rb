class SyncStaticPageTemplateContent < ActiveRecord::Migration[8.1]
  class MigrationStaticPage < ApplicationRecord
    self.table_name = "static_pages"
    has_rich_text :body
  end

  def up
    StaticPageDefaults.definitions.each do |attributes|
      page = MigrationStaticPage.find_by(system_key: attributes.fetch(:system_key))
      next unless page

      page.update!(
        slug: attributes.fetch(:slug),
        title: attributes.fetch(:title),
        kicker: attributes.fetch(:kicker),
        intro: attributes.fetch(:intro),
        body: attributes.fetch(:body)
      )
    end
  end

  def down
  end
end
