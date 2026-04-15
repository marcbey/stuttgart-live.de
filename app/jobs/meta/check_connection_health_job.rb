module Meta
  class CheckConnectionHealthJob < ApplicationJob
    def perform
      Meta::ConnectionHealthCheck.new.call
    end
  end
end
