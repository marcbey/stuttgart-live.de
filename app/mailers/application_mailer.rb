class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.configuration.x.mailer_from || "no-reply@example.com" }
  layout "mailer"
end
