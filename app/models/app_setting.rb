class AppSetting < ApplicationRecord
  SKS_PROMOTER_IDS_KEY = "sks_promoter_ids".freeze
  SKS_ORGANIZER_NOTES_KEY = "sks_organizer_notes".freeze
  MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY = "merge_artist_similarity_matching_enabled".freeze

  validates :key, presence: true, uniqueness: true
  validate :sks_promoter_ids_must_be_present

  after_commit { self.class.reset_cache! }

  class << self
    def sks_promoter_ids
      @sks_promoter_ids ||= normalize_id_list(find_by(key: SKS_PROMOTER_IDS_KEY)&.value)
    end

    def sks_organizer_notes
      @sks_organizer_notes ||= normalize_text(find_by(key: SKS_ORGANIZER_NOTES_KEY)&.value)
    end

    def sks_promoter_ids_record
      find_or_initialize_by(key: SKS_PROMOTER_IDS_KEY)
    end

    def sks_organizer_notes_record
      find_or_initialize_by(key: SKS_ORGANIZER_NOTES_KEY)
    end

    def merge_artist_similarity_matching_enabled_record
      find_or_initialize_by(key: MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY)
    end

    def merge_artist_similarity_matching_enabled?
      @merge_artist_similarity_matching_enabled =
        if @merge_artist_similarity_matching_enabled.nil?
          setting = find_by(key: MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY)
          setting.nil? ? true : normalize_boolean(setting.value)
        else
          @merge_artist_similarity_matching_enabled
        end
    end

    def normalize_id_list(value)
      raw_values =
        case value
        when String
          value.split(/[\n,]/)
        when Array
          value
        else
          Array(value)
        end

      raw_values
        .map { |entry| entry.to_s.strip }
        .reject(&:blank?)
        .uniq
    end

    def normalize_text(value)
      case value
      when String
        value.strip.presence
      when Array
        value.join("\n").strip.presence
      else
        value.to_s.strip.presence
      end
    end

    def normalize_boolean(value)
      case value
      when true, 1, "1", "true", "TRUE", "yes", "on" then true
      else
        false
      end
    end

    def reset_cache!
      @sks_promoter_ids = nil
      @sks_organizer_notes = nil
      @merge_artist_similarity_matching_enabled = nil
    end
  end

  def sks_promoter_ids
    self.class.normalize_id_list(value)
  end

  def sks_organizer_notes
    self.class.normalize_text(value)
  end

  def sks_promoter_ids_text
    sks_promoter_ids.join("\n")
  end

  def sks_promoter_ids_text=(raw_value)
    self.value = self.class.normalize_id_list(raw_value)
  end

  def sks_organizer_notes_text
    sks_organizer_notes.to_s
  end

  def sks_organizer_notes_text=(raw_value)
    self.value = self.class.normalize_text(raw_value)
  end

  def merge_artist_similarity_matching_enabled
    if key == MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY && new_record? && (value.nil? || value == [])
      return self.class.merge_artist_similarity_matching_enabled?
    end

    self.class.normalize_boolean(value)
  end

  def merge_artist_similarity_matching_enabled=(raw_value)
    self.value = self.class.normalize_boolean(raw_value)
  end

  private

  def sks_promoter_ids_must_be_present
    return unless key == SKS_PROMOTER_IDS_KEY
    return if self.class.normalize_id_list(value).any?

    errors.add(:value, "muss mindestens eine Promoter-ID enthalten")
  end
end
