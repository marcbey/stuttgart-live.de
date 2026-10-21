module PreparesPublicImages
  extend ActiveSupport::Concern

  included do
    class_attribute :public_image_slots, default: []
    after_save :remember_public_image_changes
    after_commit :enqueue_public_image_changes, on: %i[create update]
  end

  private

  def remember_public_image_changes
    @public_images_changed = public_image_slots.any? { |slot| attachment_changes.key?(slot.to_s) }
  end

  def enqueue_public_image_changes
    return unless @public_images_changed

    @public_images_changed = false
    EventImages::PreparePublicImagesJob.perform_later(self)
  end
end
