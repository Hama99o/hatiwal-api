class Conversation < ApplicationRecord
  belongs_to :listing
  belongs_to :buyer,  class_name: User.name, foreign_key: :buyer_id
  belongs_to :seller, class_name: User.name, foreign_key: :seller_id
  has_many :messages, dependent: :destroy

  enum :status, { open: 0, closed: 1 }

  validates :listing_id, uniqueness: { scope: :buyer_id, message: "already has a conversation with this buyer" }
  validate :buyer_is_not_seller

  scope :ordered, -> { order(last_message_at: :desc, created_at: :desc) }
  scope :for_user, ->(user_id) {
    where("buyer_id = ? OR seller_id = ?", user_id, user_id)
  }

  def participant?(user)
    buyer_id == user.id || seller_id == user.id
  end

  def other_participant(user)
    buyer_id == user.id ? seller : buyer
  end

  # The newest message — memoized so list serialization reads body + kind in one query.
  def last_message
    @last_message ||= messages.ordered.last
  end

  private

  def buyer_is_not_seller
    errors.add(:base, "buyer and seller must be different users") if buyer_id == seller_id
  end
end
