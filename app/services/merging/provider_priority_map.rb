module Merging
  class ProviderPriorityMap
    FALLBACK_PRIORITIES = {
      "easyticket" => 0,
      "eventim" => 10,
      "reservix" => 20
    }.freeze

    def self.call
      configured = ProviderPriority.active.ordered.pluck(:source_type, :priority_rank).to_h
      FALLBACK_PRIORITIES.merge(configured)
    end
  end
end
