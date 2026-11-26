class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Bitte später erneut versuchen." }

  def new
  end

  def create
    candidate_user = User.find_by(email_address: normalized_email_address)

    if candidate_user&.login_locked?
      LoginAttempt.log(outcome: "locked")
      redirect_to new_session_path, alert: "Zu viele Fehlversuche. Bitte später erneut versuchen."
    elsif authenticated_user = User.authenticate_by(email_address: normalized_email_address, password: params[:password].to_s)
      authenticated_user.clear_failed_login_attempts! if authenticated_user.failed_login_attempts.positive? || authenticated_user.locked_until.present?
      LoginAttempt.log(outcome: "successful")
      start_new_session_for(authenticated_user)
      redirect_to after_authentication_url
    else
      candidate_user&.register_failed_login!
      LoginAttempt.log(outcome: "failed")
      redirect_to new_session_path, alert: "E-Mail oder Passwort ist ungültig."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private
    def normalized_email_address
      params[:email_address].to_s.strip.downcase
    end
end
