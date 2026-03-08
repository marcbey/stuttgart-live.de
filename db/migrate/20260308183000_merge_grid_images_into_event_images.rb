class MergeGridImagesIntoEventImages < ActiveRecord::Migration[8.0]
  class MigrationEvent < ApplicationRecord
    self.table_name = "events"
  end

  class MigrationEventImage < ApplicationRecord
    self.table_name = "event_images"
  end

  def up
    MigrationEvent.find_each do |event|
      event_images = MigrationEventImage.where(event_id: event.id).order(:created_at, :id)
      detail_hero = event_images.find_by(purpose: "detail_hero")
      grid_images = event_images.where(purpose: "grid_tile").to_a
      next if grid_images.empty? && detail_hero.blank?

      preferred_grid_image =
        grid_images.find { |image| image.grid_variant.present? && image.grid_variant != "1x1" } ||
        grid_images.find { |image| image.grid_variant.present? } ||
        grid_images.first

      if detail_hero.present?
        apply_grid_settings!(detail_hero, preferred_grid_image) if preferred_grid_image.present?
      elsif preferred_grid_image.present?
        preferred_grid_image.update_columns(purpose: "detail_hero")
        detail_hero = preferred_grid_image
      end

      next if detail_hero.blank?

      grid_images.each do |grid_image|
        next if grid_image.id == detail_hero.id

        grid_image.destroy!
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "grid images were merged into event images"
  end

  private

  def apply_grid_settings!(detail_hero, grid_image)
    detail_hero.update_columns(
      grid_variant: grid_image.grid_variant,
      card_focus_x: grid_image.card_focus_x,
      card_focus_y: grid_image.card_focus_y,
      card_zoom: grid_image.card_zoom
    )
  end
end
