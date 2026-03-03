module Merging
  class ProviderPriorityMap
    FALLBACK_PRIORITIES = {
      "reservix" => 10,
      "eventim" => 20,
      "easyticket" => 30
    }.freeze

    def self.call
      configured = ProviderPriority.active.ordered.pluck(:source_type, :priority_rank).to_h
      FALLBACK_PRIORITIES.merge(configured)
    end
  end
end
