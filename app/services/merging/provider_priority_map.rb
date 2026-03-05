module Merging
  class ProviderPriorityMap
    FALLBACK_PRIORITIES = {
      "easyticket" => 10,
      "eventim" => 20,
      "reservix" => 30
    }.freeze

    def self.call
      configured = ProviderPriority.active.ordered.pluck(:source_type, :priority_rank).to_h
      FALLBACK_PRIORITIES.merge(configured)
    end
  end
end
