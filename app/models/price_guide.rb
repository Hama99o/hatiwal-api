# IDEA-4 (docs/PRICE_GUIDE.md): what similar items sold for, per subcategory +
# currency, over the last 90 days — a P25–P75 range, published only with
# enough sales from enough different sellers (one shop is not "the market",
# and a thin bucket would reveal a single sale). Built by PriceGuides::Builder.
class PriceGuide < ApplicationRecord
  MIN_SALES = 5
  MIN_SELLERS = 3
  WINDOW = 90.days
  # Prices there are rents, salaries, rates or a mix: no guide (Stays go by kind).
  EXCLUDED_ROOT_SLUGS = %w[jobs services property other].freeze

  belongs_to :category

  validates :currency, presence: true, uniqueness: { scope: :category_id }

  # The owner decides if buyers see it (default off): one server switch, no app release.
  def self.buyers_enabled?
    ENV.fetch("PRICE_GUIDE_BUYERS", "0") == "1"
  end

  def self.published?(sales_count, sellers_count)
    sales_count >= MIN_SALES && sellers_count >= MIN_SELLERS
  end

  # The admin page: how close each bucket is to switching on.
  def category_name = category&.name_en
  def sales_vs_threshold = "#{sales_count} / #{MIN_SALES}"
  def sellers_vs_threshold = "#{sellers_count} / #{MIN_SELLERS}"

  # What the apps receive: the range and the count, or only `available: false`.
  def payload
    return { available: false } unless available?

    { available: true, low: low.to_f, high: high.to_f, count: sales_count, currency: currency, window_days: WINDOW.in_days.to_i }
  end
end
