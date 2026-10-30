# IDEA-4: rebuilds every price-guide bucket from the SOLD transactions of the
# last 90 days (per-unit final_price; docs/PRICE_GUIDE.md §1).
#  - bucket = the listing's category + the sale's currency (AFN and PKR never mix);
#  - typos dropped first: prices outside 0.2×–5× the bucket median;
#  - published (P25–P75, rounded outward) only with ≥ 5 sales from ≥ 3 sellers;
#  - every bucket is kept as counts, so the admin sees what is close.
module PriceGuides
  class Builder
    TRIM = (0.2..5.0)

    def self.call(now: Time.current) = new(now).call

    def initialize(now)
      @now = now
    end

    def call
      rows = buckets.map { |(category_id, currency), sales| row(category_id, currency, sales) }
      PriceGuide.transaction do
        PriceGuide.delete_all
        PriceGuide.insert_all(rows) if rows.any?
      end
      rows.size
    end

    private

    def buckets
      Transaction.sold
                 .where(completed_at: (@now - PriceGuide::WINDOW)..@now)
                 .joins(listing: :category)
                 .where(categories: { kind: Category::KIND_ITEM })
                 .where.not(listings: { category_id: excluded_category_ids })
                 .pluck("listings.category_id", :currency, :final_price, :seller_id)
                 .group_by { |category_id, currency, _price, _seller| [ category_id, currency ] }
    end

    def excluded_category_ids
      Category.self_and_children(Category.where(slug: PriceGuide::EXCLUDED_ROOT_SLUGS).select(:id)).pluck(:id)
    end

    def row(category_id, currency, sales)
      kept = trimmed(sales)
      prices = kept.map { |_c, _cur, price, _s| price.to_f }.sort
      sellers = kept.map(&:last).uniq.size
      available = PriceGuide.published?(kept.size, sellers)
      { category_id: category_id, currency: currency, sales_count: kept.size, sellers_count: sellers,
        available: available,
        low: (available ? round_down(percentile(prices, 0.25)) : nil),
        high: (available ? round_up(percentile(prices, 0.75)) : nil),
        refreshed_at: @now, created_at: @now, updated_at: @now }
    end

    def trimmed(sales)
      median = percentile(sales.map { |s| s[2].to_f }.sort, 0.5)
      sales.select { |s| TRIM.cover?(s[2].to_f / median) }
    end

    # Linear interpolation between the closest ranks (as PostgreSQL percentile_cont).
    def percentile(sorted, fraction)
      pos = (sorted.size - 1) * fraction
      lower = sorted[pos.floor]
      upper = sorted[pos.ceil]
      lower + ((upper - lower) * (pos - pos.floor))
    end

    def step(value)
      if value < 10_000 then 100
      elsif value < 100_000 then 500
      else 5_000
      end
    end

    def round_down(value) = (value / step(value)).floor * step(value)
    def round_up(value) = (value / step(value)).ceil * step(value)
  end
end
