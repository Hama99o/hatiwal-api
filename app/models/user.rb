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
  validates :push_token, length: { maximum: 200 }, allow_blank: true

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

  # ── Response rate ────────────────────────────────────────────────────────────
  #
  # All response-rate logic is driven by a single memoized computation
  # (seller_response_stats) so the database query runs AT MOST ONCE per
  # request/object — regardless of how many times the serializer calls
  # response_rate_percent or response_time_label.
  #
  # Public helpers:
  #
  #   response_rate_percent  → Integer 0-100, or nil (threshold not met)
  #   response_time_label    → Symbol (:within_one_hour / :within_a_day /
  #                            :within_a_few_days), or nil (threshold not met)

  ResponseStats = Data.define(:rate_percent, :time_label)

  def response_rate_percent
    seller_response_stats.rate_percent
  end

  def response_time_label
    seller_response_stats.time_label
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

  private

  # Loads the seller's recent conversations exactly once and derives both
  # the rate percentage and the time-label bucket in a single pass.
  # The result is memoized on the model instance for the lifetime of the
  # object, preventing duplicate queries when the serializer reads both
  # attributes in the same request.
  def seller_response_stats
    @seller_response_stats ||= compute_seller_response_stats
  end

  def compute_seller_response_stats
    window_convos = seller_conversations
                    .where(created_at: 90.days.ago..)
                    .includes(:messages)
                    .to_a   # materialise once; all further work is in-memory

    if window_convos.size < 5
      return ResponseStats.new(rate_percent: nil, time_label: nil)
    end

    replied_count  = 0
    response_times = []

    window_convos.each do |conv|
      buyer_msgs  = conv.messages.select { |m| m.user_id == conv.buyer_id }
      seller_msgs = conv.messages.select { |m| m.user_id == id }

      first_buyer_msg = buyer_msgs.min_by(&:created_at)
      next unless first_buyer_msg

      # Seller messages that arrived AFTER the first buyer message
      seller_replies = seller_msgs.select { |sm| sm.created_at > first_buyer_msg.created_at }
      first_reply    = seller_replies.min_by(&:created_at)

      if first_reply
        elapsed = first_reply.created_at - first_buyer_msg.created_at
        response_times << elapsed
        replied_count += 1 if elapsed <= 24.hours
      end
    end

    rate_percent = (replied_count.to_f / window_convos.size * 100).round

    time_label =
      if response_times.empty?
        :within_a_few_days
      else
        sorted = response_times.sort
        median = sorted[sorted.size / 2]
        if median <= 1.hour
          :within_one_hour
        elsif median <= 24.hours
          :within_a_day
        else
          :within_a_few_days
        end
      end

    ResponseStats.new(rate_percent: rate_percent, time_label: time_label)
  end
end
