class AddServiceStaticPages < ActiveRecord::Migration[8.1]
  class MigrationStaticPage < ApplicationRecord
    self.table_name = "static_pages"

    has_rich_text :body
  end

  def up
    StaticPageDefaults.definitions.each do |attributes|
      next unless %w[contact faq about].include?(attributes.fetch(:system_key))

      page = MigrationStaticPage.find_by(system_key: attributes.fetch(:system_key)) ||
        MigrationStaticPage.find_by(slug: attributes.fetch(:slug)) ||
        MigrationStaticPage.new

      page.system_key = attributes.fetch(:system_key)
      page.slug = attributes.fetch(:slug)
      page.title = attributes.fetch(:title)
      page.kicker = attributes[:kicker]
      page.intro = attributes.fetch(:intro)
      page.body = attributes.fetch(:body)
      page.save!
    end
  end

  def down
    MigrationStaticPage.where(system_key: %w[faq about]).find_each(&:destroy!)
  end
end
