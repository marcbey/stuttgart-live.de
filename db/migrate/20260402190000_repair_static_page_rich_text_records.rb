class RepairStaticPageRichTextRecords < ActiveRecord::Migration[8.1]
  class MigrationStaticPage < ApplicationRecord
    self.table_name = "static_pages"
  end

  def up
    ActionText::RichText.where(record_type: legacy_record_types, name: "body").delete_all

    StaticPageDefaults.definitions.each do |attributes|
      page = MigrationStaticPage.find_by(system_key: attributes.fetch(:system_key))
      next unless page

      page.update_columns(
        slug: attributes.fetch(:slug),
        title: attributes.fetch(:title),
        kicker: attributes.fetch(:kicker),
        intro: attributes.fetch(:intro),
        updated_at: Time.current
      )

      rich_text = ActionText::RichText.find_or_initialize_by(
        record_type: "StaticPage",
        record_id: page.id,
        name: "body"
      )
      rich_text.body = attributes.fetch(:body)
      rich_text.save!
    end
  end

  def down
  end

  private
    def legacy_record_types
      [
        "CreateStaticPages::MigrationStaticPage",
        "SyncStaticPageTemplateContent::MigrationStaticPage"
      ]
    end
end
