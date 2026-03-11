require "set"

module Importing
  class ImportEventImagesSync
    def self.call(owner:, candidates:, source: nil)
      new(owner: owner, candidates: candidates, source: source).call
    end

    def initialize(owner:, candidates:, source:)
      @owner = owner
      @candidates = candidates
      @source = source
    end

    def call
      existing_by_key = owner.import_event_images.index_by do |image|
        image_key(source: image.source, image_type: image.image_type, image_url: image.image_url)
      end
      changed = false

      normalized_candidates.each_with_index do |candidate, index|
        key = image_key(
          source: candidate[:source],
          image_type: candidate[:image_type],
          image_url: candidate[:image_url]
        )
        image = existing_by_key.delete(key) || owner.import_event_images.new
        image.assign_attributes(candidate.merge(position: index))
        next unless image.new_record? || image.changed?

        image.save!
        changed = true
      end

      existing_by_key.each_value do |image|
        image.destroy!
        changed = true
      end

      changed
    end

    private

    attr_reader :owner, :candidates, :source

    def normalized_candidates
      @normalized_candidates ||= begin
        seen = Set.new

        Array(candidates).filter_map do |candidate|
          row = candidate.respond_to?(:to_h) ? candidate.to_h : {}
          image_url = ImportEventImage.normalize_image_url(row[:image_url] || row["image_url"])
          next if image_url.blank?

          normalized_source = normalized_source_for(row)
          next if normalized_source.blank?

          image_type = (row[:image_type] || row["image_type"]).to_s.strip.presence || "image"
          key = image_key(source: normalized_source, image_type: image_type, image_url: image_url)
          next if seen.include?(key)

          seen << key
          {
            source: normalized_source,
            image_type: image_type,
            image_url: image_url,
            role: normalized_role_for(row, source: normalized_source, image_type: image_type),
            aspect_hint: normalized_aspect_hint_for(row, image_url: image_url, image_type: image_type)
          }
        end
      end
    end

    def normalized_source_for(row)
      (row[:source] || row["source"]).to_s.strip.presence || source.to_s.strip.presence
    end

    def normalized_role_for(row, source:, image_type:)
      (row[:role] || row["role"]).to_s.strip.presence ||
        ImportEventImage.derive_role(source: source, image_type: image_type)
    end

    def normalized_aspect_hint_for(row, image_url:, image_type:)
      (row[:aspect_hint] || row["aspect_hint"]).to_s.strip.presence ||
        ImportEventImage.derive_aspect_hint(url: image_url, image_type: image_type)
    end

    def image_key(source:, image_type:, image_url:)
      [
        source.to_s.strip.downcase,
        image_type.to_s.strip,
        image_url.to_s.strip.downcase
      ]
    end
  end
end
