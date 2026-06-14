class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  include DeviseTokenAuth::Concerns::User

  has_one_attached :avatar

  enum :status, { active: 0, suspended: 1, banned: 2 }

  has_many :listings, dependent: :destroy
  has_many :saved_listings, dependent: :destroy
  has_many :saved_listing_items, through: :saved_listings, source: :listing
  has_many :buyer_conversations, class_name: Conversation.name, foreign_key: :buyer_id, dependent: :destroy, inverse_of: :buyer
  has_many :seller_conversations, class_name: Conversation.name, foreign_key: :seller_id, dependent: :destroy, inverse_of: :seller
  has_many :messages, dependent: :destroy
  has_many :filed_reports, class_name: Report.name, foreign_key: :reporter_id, dependent: :destroy, inverse_of: :reporter
  has_many :blocks_as_blocker, class_name: Block.name, foreign_key: :blocker_id, dependent: :destroy, inverse_of: :blocker
  has_many :blocks_as_blocked, class_name: Block.name, foreign_key: :blocked_id, dependent: :destroy, inverse_of: :blocked
  has_many :blocked_users, through: :blocks_as_blocker, source: :blocked
  has_many :blocking_users, through: :blocks_as_blocked, source: :blocker
  has_many :saved_searches, dependent: :destroy
  has_many :listing_views, dependent: :destroy
  has_many :viewed_listings, through: :listing_views, source: :listing

  validates :firstname, presence: true
  validates :lastname, presence: true
  validates :preferred_language, inclusion: { in: %w[en ps fa] }, allow_blank: true
  validates :preferred_theme, inclusion: { in: %w[light dark system] }, allow_blank: true

  def full_name
    "#{firstname} #{lastname}".strip
  end

  def blocked?(other_user)
    blocked_users.exists?(other_user.id)
  end

  def blocked_by?(other_user)
    blocking_users.exists?(other_user.id)
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
