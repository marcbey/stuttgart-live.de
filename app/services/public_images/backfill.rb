module PublicImages
  class Backfill
    def initialize(limit:, event_ids: [], event_slugs: [], dry_run: true)
      @limit = Integer(limit)
      raise ArgumentError, "LIMIT must be between 1 and 100" unless (1..100).cover?(@limit)

      @event_ids, @event_slugs, @dry_run = event_ids, event_slugs, dry_run
    end

    def call
      scope = Event.published_live.where(start_at: Time.current.beginning_of_day..)
      scope = scope.where(id: @event_ids) if @event_ids.present?
      scope = scope.where(slug: @event_slugs) if @event_slugs.present?
      records = []
      scope.limit(@limit).each do |event|
        records << event if event.public_image_slots.any? { |slot| event.public_send(slot).attached? }
        records.concat(event.event_images.limit(@limit).to_a)
        records.concat(event.import_event_images.limit(@limit).to_a)
        break if records.size >= @limit
      end
      records = records.first(@limit)
      records.each { |record| EventImages::PreparePublicImagesJob.perform_later(record) } unless @dry_run
      records
    end
  end
end
