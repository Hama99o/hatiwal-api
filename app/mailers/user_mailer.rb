# frozen_string_literal: true

class UserMailer < ApplicationMailer
  # reset_password(user, raw_token)
  #
  # Sends a branded password-reset email. The raw_token is the pre-hashing
  # value returned by Devise.token_generator.generate — it goes into the URL;
  # only its digest is stored in the database.
  def reset_password(user, raw_token)
    @user      = user
    @token     = raw_token
    @reset_url = "#{ENV.fetch('WEB_RESET_URL', 'https://hatiwal.com/reset-password')}?token=#{@token}"

    mail(to: user.email, subject: "Reset your Hatiwal password")
  end
end
