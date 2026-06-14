class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user
  # A meetup accept/decline points back to the proposal it answers.
  belongs_to :responds_to, class_name: "Message", optional: true

  has_one_attached :attachment

  enum :kind, {
    text: 0, meetup_proposal: 1, system: 2, offer: 3, document: 4, image_message: 5,
    meetup_accepted: 6, meetup_declined: 7, offer_accepted: 8, offer_declined: 9
  }

  validates :body, presence: true, length: { maximum: 1000 }

  scope :ordered, -> { order(:created_at) }

  after_create :update_conversation_last_message_at

  def read?
    read_at.present?
  end

  def mark_read!
    update_column(:read_at, Time.current) if read_at.nil?
  end

  private

  def update_conversation_last_message_at
    conversation.update_column(:last_message_at, created_at)
  end
end
