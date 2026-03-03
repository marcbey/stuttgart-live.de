require "net/http"
require "timeout"

module Importing
  module RetryPolicy
    RETRY_DELAYS = [ 30.seconds, 1.minute, 5.minutes ].freeze
    RETRY_ATTEMPTS = RETRY_DELAYS.size + 1

    TRANSIENT_ERRORS = [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Timeout::Error,
      Errno::ECONNRESET,
      Errno::ETIMEDOUT,
      SocketError,
      EOFError
    ].freeze

    def self.delay_for(executions)
      RETRY_DELAYS.fetch(executions - 1, RETRY_DELAYS.last)
    end
  end
end
