# Staff account for the server-rendered admin dashboard (Administrate, /admin).
#
# Deliberately SEPARATE from User: marketplace users authenticate via
# devise_token_auth (API tokens), while admins use plain session/cookie login
# in a browser. Keeping them in different tables means a marketplace user can
# never escalate into an admin, and the admin surface shares no auth code with
# the public API.
#
# Admin accounts are created out-of-band (seeds / rails console) — there is no
# public registration route.
class AdminUser < ApplicationRecord
  devise :database_authenticatable,
         :recoverable,
         :rememberable,
         :trackable,
         :timeoutable,
         :lockable,
         :validatable

  # Use our branded AdminUserMailer instead of Devise's default mailer for
  # password-reset emails (the default would send from devise@example.com).
  def send_devise_notification(notification, *args)
    if notification == :reset_password_instructions
      AdminUserMailer.reset_password_instructions(self, *args).deliver_later
    else
      super
    end
  end

  validates :name, presence: true

  def to_s
    name.presence || email
  end
end
