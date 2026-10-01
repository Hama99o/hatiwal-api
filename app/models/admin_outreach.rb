# One thing an admin sent to one person — email, in-app, or both. The unit of
# the Messages history. Created only by Admin::SendMessage.
class AdminOutreach < ApplicationRecord
  belongs_to :admin_user
  belongs_to :user
  belongs_to :admin_email, optional: true
  belongs_to :message, optional: true

  enum :source, { compose: 0, support_inbox: 1 }

  scope :recent, -> { order(created_at: :desc) }

  def channels
    [ ("Email" if via_email?), ("In-app" if via_in_app?) ].compact
  end
end
