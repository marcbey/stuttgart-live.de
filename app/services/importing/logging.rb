require "logger"

module Importing
  module Logging
    module_function

    def logger
      @logger ||= begin
        file_logger = ::Logger.new(Rails.root.join("log", "importers.log"))
        file_logger.formatter = proc do |severity, timestamp, _progname, message|
          "#{timestamp.iso8601} #{severity} #{message}\n"
        end
        ActiveSupport::TaggedLogging.new(file_logger)
      end
    end
  end
end
