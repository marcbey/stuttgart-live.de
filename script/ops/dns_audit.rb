require_relative "dns_change_policy"

module Ops
  module DnsAudit
    def self.violations(before:, after:, allowance:)
      zone = before.fetch("zone")
      valid = DnsChangePolicy::ZONES.include?(zone) && after.fetch("zone") == zone && allowance.fetch("zone") == zone &&
        before["inventory_complete"] == true && after["inventory_complete"] == true &&
        before["provider_controls"].is_a?(Hash) && after["provider_controls"].is_a?(Hash)
      raise ArgumentError, "Zonen oder vollständige Providerinventare fehlen" unless valid
      errors = DnsChangePolicy.violations(before: before.fetch("records"), after: after.fetch("records"), allowed_changes: allowance.fetch("changes"))
      old, current = before.fetch("provider_controls"), after.fetch("provider_controls")
      allowed_controls = allowance.fetch("provider_control_changes", [])
      (old.keys | current.keys).each do |key|
        next if old[key] == current[key] && old.key?(key) == current.key?(key)
        allowed = %w[ipv4 ipv6 redirect existing_subdomains].include?(key) && allowed_controls.include?({ "key" => key, "before" => old[key], "after" => current[key] })
        if key == "existing_subdomains"
          added = Array(current[key]) - Array(old[key])
          removed = Array(old[key]) - Array(current[key])
          allowed &&= (added + removed).all? { |name| name == "staging.#{zone}" }
        end
        errors << "Nicht erlaubte Provideränderung: #{key}" unless allowed
      end
      errors
    end
  end
end
