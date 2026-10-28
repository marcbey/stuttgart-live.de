class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.configuration.x.mailer_from || "no-reply@example.com" }
  helper BrandHelper
  layout "mailer"
end
