class AppSetting < ApplicationRecord
  SKS_PROMOTER_IDS_KEY = "sks_promoter_ids".freeze

  validates :key, presence: true, uniqueness: true
  validate :sks_promoter_ids_must_be_present

  after_commit { self.class.reset_cache! }

  class << self
    def sks_promoter_ids
      @sks_promoter_ids ||= normalize_id_list(find_by(key: SKS_PROMOTER_IDS_KEY)&.value)
    end

    def sks_promoter_ids_record
      find_or_initialize_by(key: SKS_PROMOTER_IDS_KEY)
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

    def reset_cache!
      @sks_promoter_ids = nil
    end
  end

  def sks_promoter_ids
    self.class.normalize_id_list(value)
  end

  def sks_promoter_ids_text
    sks_promoter_ids.join("\n")
  end

  def sks_promoter_ids_text=(raw_value)
    self.value = self.class.normalize_id_list(raw_value)
  end

  private

  def sks_promoter_ids_must_be_present
    return unless key == SKS_PROMOTER_IDS_KEY
    return if self.class.normalize_id_list(value).any?

    errors.add(:value, "muss mindestens eine Promoter-ID enthalten")
  end
end
