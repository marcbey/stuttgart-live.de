class AddTicketsStaticPage < ActiveRecord::Migration[8.1]
  class MigrationStaticPage < ApplicationRecord
    self.table_name = "static_pages"

    has_rich_text :body
  end

  def up
    attributes = StaticPageDefaults.definitions.find { |definition| definition.fetch(:system_key) == "tickets" }

    page = MigrationStaticPage.find_by(system_key: attributes.fetch(:system_key)) ||
      MigrationStaticPage.find_by(slug: attributes.fetch(:slug)) ||
      MigrationStaticPage.new

    body_missing = page.body.to_plain_text.blank?

    page.system_key ||= attributes.fetch(:system_key)
    page.slug ||= attributes.fetch(:slug)
    page.title ||= attributes.fetch(:title)
    page.kicker ||= attributes[:kicker]
    page.intro ||= attributes.fetch(:intro)
    page.body = attributes.fetch(:body) if body_missing
    page.save! if page.new_record? || page.changed? || body_missing
  end

  def down
    MigrationStaticPage.find_by(system_key: "tickets")&.destroy!
  end
end
