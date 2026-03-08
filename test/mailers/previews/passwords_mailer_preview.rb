# Preview all emails at http://localhost:3000/rails/mailers/passwords_mailer
class PasswordsMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/passwords_mailer/magic_link
  def magic_link
    PasswordsMailer.magic_link(User.find_by!(role: "admin"))
  end
end
