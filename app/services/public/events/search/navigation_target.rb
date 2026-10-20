module Public
  module Events
    module Search
      class NavigationTarget
        def self.call(query)
          return unless Normalizer.normalize(query) == "russ live"

          LaneDirectory.russ_live
        end
      end
    end
  end
end
