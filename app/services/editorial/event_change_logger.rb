module Editorial
  class EventChangeLogger
    def self.log!(event:, action:, user:, changed_fields: {}, metadata: {})
      event.event_change_logs.create!(
        user: user,
        action: action,
        changed_fields: normalize(changed_fields),
        metadata: normalize(metadata)
      )
    end

    def self.normalize(value)
      return {} unless value.is_a?(Hash)

      value.deep_stringify_keys
    end

    private_class_method :normalize
  end
end
