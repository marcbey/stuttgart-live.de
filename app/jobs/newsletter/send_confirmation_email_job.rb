module Newsletter
  class SendConfirmationEmailJob < ApplicationJob
    queue_as :default

    def perform(subscriber)
      Newsletter::SendConfirmationEmail.call(subscriber)
    end
  end
end
