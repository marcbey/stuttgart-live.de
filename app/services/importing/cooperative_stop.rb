module Importing
  module CooperativeStop
    module_function

    def check!(stop_requested = nil, **details)
      raise StopRequested.new(**details) if stop_requested&.call
    end
  end
end
