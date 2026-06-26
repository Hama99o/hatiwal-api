# frozen_string_literal: true

class AdminUserMailer < ApplicationMailer
  def reset_password_instructions(record, token, _opts = {})
    @admin_user = record
    @token      = token
    @reset_url  = edit_admin_user_password_url(reset_password_token: @token)

    mail(to: record.email, subject: "Hatiwal Admin — Reset your password")
  end
end
