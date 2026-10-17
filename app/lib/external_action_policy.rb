# Guard the real client boundary even for manually triggered jobs or injected credentials.
module ExternalActionPolicy
  Disabled = Class.new(StandardError)
  ACTIONS = %i[mailjet meta external_import paid_ai].freeze

  def self.require_allowed!(action:, environment: Rails.configuration.x.deployment_environment)
    raise ArgumentError, "Unknown external action" unless ACTIONS.include?(action)
    return true if %w[production development test].include?(environment)

    label = environment == "staging" ? "Staging" : environment.to_s
    raise Disabled, "Externe Aktion #{action} ist in #{label} deaktiviert."
  end
end
