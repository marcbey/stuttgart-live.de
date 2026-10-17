require "ipaddr"

module Ops
  module DnsChangePolicy
    ZONES = %w[stuttgart-live.de russ-live.de].freeze
    KEYS = %w[name type value priority ttl].sort.freeze

    def self.violations(before:, after:, allowed_changes:)
      [ before, after ].each do |records|
        raise ArgumentError, "Ungültiger oder doppelter DNS-Datensatz" unless records.is_a?(Array) && records.all? { |record| valid_record?(record) } && records.uniq == records
      end
      raise ArgumentError, "Änderungsliste muss ein Array sein" unless allowed_changes.is_a?(Array)
      old = before.map { |record| comparable(record) }
      current = after.map { |record| comparable(record) }
      changes = (old - current).map { |record| [ "remove", record ] } + (current - old).map { |record| [ "add", record ] }
      changes.filter_map do |action, record|
        permitted = allowed_changes.any? do |allow|
          allow.is_a?(Hash) && allow["action"] == action && allow["record"] == record && allowed_scope?(record, allow)
        end
        "Nicht erlaubte DNS-Änderung: #{action} #{record.fetch('name')} #{record.fetch('type')} (Wert/Priorität/TTL)" unless permitted
      end
    rescue ArgumentError => error
      [ error.message ]
    end

    def self.valid_record?(record)
      return false unless record.is_a?(Hash) && record.keys.sort == KEYS
      record["name"].is_a?(String) && record["name"].match?(/\A[a-z0-9_*.-]+\z/) &&
        record["type"].is_a?(String) && record["type"].match?(/\A[A-Z][A-Z0-9]*\z/) &&
        record["value"].is_a?(String) && !record["value"].empty? &&
        record["ttl"].is_a?(Integer) && record["ttl"].between?(0, 2**31 - 1) &&
        (record["priority"].nil? || (record["priority"].is_a?(Integer) && record["priority"].between?(0, 65_535)))
    end

    def self.comparable(record)
      return record unless record["type"] == "SOA"
      fields = record.fetch("value").split
      raise ArgumentError, "Ungültiger SOA-Datensatz" unless fields.size == 7 && fields.drop(2).all? { |field| field.match?(/\A\d+\z/) }
      fields[2] = "SERIAL"
      record.merge("value" => fields.join(" "))
    end

    def self.allowed_scope?(record, allow)
      name, type, value = record.values_at("name", "type", "value")
      zone = ZONES.find { |candidate| name == candidate || name.end_with?(".#{candidate}") }
      return false unless zone
      if %W[#{zone} www.#{zone} staging.#{zone}].include?(name) && %w[A AAAA].include?(type)
        address = IPAddr.new(value)
        return record["priority"].nil? && (type == "A" ? address.ipv4? : address.ipv6?)
      end
      return record["priority"].nil? && value.match?(/\A[a-z0-9.-]+\z/) if name == "www.#{zone}" && type == "CNAME"
      %W[_acme-challenge.#{zone} _acme-challenge.www.#{zone} _acme-challenge.staging.#{zone}].include?(name) &&
        type == "TXT" && record["priority"].nil? && allow["owned_acme_value"] == true
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
