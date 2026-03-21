module Importing
  class StopRequested < StandardError
    attr_reader :details

    def initialize(message = "Stop requested", **details)
      @details = details.deep_stringify_keys
      super(message)
    end

    def detail(key, default = nil)
      details.fetch(key.to_s, default)
    end
  end
end
