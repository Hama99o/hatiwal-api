class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user
  # A meetup accept/decline points back to the proposal it answers.
  belongs_to :responds_to, class_name: "Message", optional: true

  has_one_attached :attachment

  enum :kind, {
    text: 0, meetup_proposal: 1, system: 2, offer: 3, document: 4, image_message: 5,
    meetup_accepted: 6, meetup_declined: 7, offer_accepted: 8, offer_declined: 9,
    offer_counter: 10
  }

  # Kinds that a client (request param) is allowed to set.
  # :system is intentionally excluded — only server-side code may persist system messages.
  # :offer_counter is sendable only by the seller (recipient of the original offer);
  # the buyer then responds using the existing offer_accepted / offer_declined kinds.
  USER_SENDABLE_KINDS = %w[
    text meetup_proposal meetup_accepted meetup_declined
    offer offer_accepted offer_declined document image_message offer_counter
  ].freeze

  validates :body, presence: true, length: { maximum: 1000 }
  validate :kind_must_not_be_system_when_user_authored
  validate :responds_to_must_be_in_same_conversation, if: -> { responds_to_id.present? }

  scope :ordered,      -> { order(:created_at) }            # chronological (oldest→newest)
  scope :newest_first, -> { order(created_at: :desc) }      # paginated chat: most recent page first

  after_create :update_conversation_last_message_at

  def read?
    read_at.present?
  end

  def mark_read!
    update_column(:read_at, Time.current) if read_at.nil?
  end

  private

  # Prevents any user-authored message from being stored with kind :system.
  # Server-generated system messages bypass this by setting user to a system
  # actor or by writing directly to the DB — not via the public API.
  def kind_must_not_be_system_when_user_authored
    errors.add(:kind, :invalid) if system?
  end

  # Ensures that the message being responded to belongs to the same conversation.
  # Without this guard, a participant of conversation A could link an
  # accept/decline response to a proposal in conversation B, corrupting
  # deal-outcome state across unrelated conversations.
  def responds_to_must_be_in_same_conversation
    referenced = Message.find_by(id: responds_to_id)
    if referenced.nil?
      errors.add(:responds_to_id, :invalid)
    elsif referenced.conversation_id != conversation_id
      errors.add(:responds_to_id, :invalid)
    end
  end

  def update_conversation_last_message_at
    conversation.update_column(:last_message_at, created_at)
  end
end
