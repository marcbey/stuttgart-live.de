class PasswordsMailer < ApplicationMailer
  def magic_link(user)
    @user = user
    mail subject: "Dein Magic-Link für Stuttgart Live", to: user.email_address
  end
end
