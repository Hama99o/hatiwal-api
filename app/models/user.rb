class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  include DeviseTokenAuth::Concerns::User

  enum :status, { active: 0, suspended: 1, banned: 2 }

  has_many :listings, dependent: :destroy
  has_many :saved_listings, dependent: :destroy
  has_many :saved_listing_items, through: :saved_listings, source: :listing
  has_many :buyer_conversations, class_name: Conversation.name, foreign_key: :buyer_id, dependent: :destroy
  has_many :seller_conversations, class_name: Conversation.name, foreign_key: :seller_id, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :filed_reports, class_name: Report.name, foreign_key: :reporter_id, dependent: :destroy

  validates :firstname, presence: true
  validates :lastname, presence: true
  validates :preferred_language, inclusion: { in: %w[en ps fa] }, allow_blank: true

  def full_name
    "#{firstname} #{lastname}".strip
  end

  def conversations
    Conversation.where("buyer_id = ? OR seller_id = ?", id, id)
  end

  def self.search_by_name(query)
    return all if query.blank?

    words = query.to_s.strip.split(/\s+/)
    result = all

    words.each do |word|
      term = "%#{word.downcase}%"
      result = result.where(
        "LOWER(firstname) LIKE ? OR LOWER(lastname) LIKE ?",
        term, term
      )
    end

    result
  end
end
