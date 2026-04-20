class UseDuAddressInOrganizerNotes < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  class EventMigration < ActiveRecord::Base
    self.table_name = "events"
  end

  REPLACEMENTS = {
    "Wir danken für Ihr Verständnis!" => "Danke für euer Verständnis!",
    "Sie erreichen unsere Tickethotline" => "Unsere Tickethotline erreichst du",
    "findest Du" => "findest du"
  }.freeze

  def up
    update_default_organizer_notes
    update_app_setting_notes
    update_event_notes
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "organizer notes were updated to du address"
  end

  private

  def update_default_organizer_notes
    old_default = EventMigration.column_defaults["organizer_notes"]
    new_default = du_addressed_text(old_default)

    change_column_default :events, :organizer_notes, from: old_default, to: new_default if new_default != old_default
  end

  def update_app_setting_notes
    AppSettingMigration.where(key: "sks_organizer_notes").find_each do |setting|
      new_value = du_addressed_text(setting.value)
      setting.update!(value: new_value) if new_value != setting.value
    end
  end

  def update_event_notes
    EventMigration.where.not(organizer_notes: [ nil, "" ]).find_each do |event|
      new_notes = du_addressed_text(event.organizer_notes)
      event.update_columns(organizer_notes: new_notes, updated_at: Time.current) if new_notes != event.organizer_notes
    end
  end

  def du_addressed_text(text)
    return text if text.blank?

    REPLACEMENTS.reduce(text.to_s) do |copy, (formal_address, du_address)|
      copy.gsub(formal_address, du_address)
    end
  end
end
