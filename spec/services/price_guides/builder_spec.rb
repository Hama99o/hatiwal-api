require "rails_helper"

# IDEA-4 price guide (docs/PRICE_GUIDE.md): one bucket per subcategory +
# currency, from SOLD transactions of the last 90 days. A range is published only
# with ≥ 5 sales from ≥ 3 different sellers, after trimming typos; never a
# single value, never one sale's price.
RSpec.describe PriceGuides::Builder do
  include ActiveSupport::Testing::TimeHelpers

  let(:phones)  { create(:category, :with_parent, kind: "item") }
  let(:sellers) { create_list(:user, 3) }

  def sale(price, seller: sellers.first, category: phones, currency: "AFN", at: 3.days.ago, status: :outside_buyer)
    listing = create(:listing, :active, user: seller, category: category, price: price, currency: currency)
    create(:transaction, status, seller: seller, listing: listing, final_price: price, currency: currency, completed_at: at)
  end

  def five_sales(prices = [ 8150, 9230, 10_040, 11_120, 12_000 ], sellers_used: sellers)
    prices.each_with_index { |p, i| sale(p, seller: sellers_used[i % sellers_used.size]) }
  end

  def guide = PriceGuide.find_by(category: phones, currency: "AFN")

  it "5 sales from 3 sellers: P25–P75, rounded outward to a readable step" do
    five_sales
    described_class.call
    expect(guide).to have_attributes(available: true, sales_count: 5, sellers_count: 3, low: 9_200, high: 11_500)
  end

  it "4 sales: kept as a count for the admin, but not available" do
    five_sales([ 8000, 9000, 10_000, 11_000 ])
    described_class.call
    expect(guide).to have_attributes(available: false, sales_count: 4, low: nil, high: nil)
  end

  it "5 sales from only 2 sellers: not available (one shop is not the market)" do
    five_sales(sellers_used: sellers.first(2))
    described_class.call
    expect(guide).to have_attributes(available: false, sellers_count: 2, low: nil, high: nil)
  end

  it "drops a typo (45 among ~10,000s) before counting and ranging" do
    five_sales
    sale(45, seller: sellers.last)
    described_class.call
    expect(guide).to have_attributes(available: true, sales_count: 5, low: 9_200, high: 11_500)
  end

  it "counts only sold sales of the last 90 days" do
    five_sales([ 8000, 9000, 10_000, 11_000 ])
    sale(12_000, at: 91.days.ago, seller: sellers.last)
    sale(12_000, seller: sellers.last, status: :reserved)
    described_class.call
    expect(guide.sales_count).to eq(4)
  end

  it "never mixes currencies" do
    five_sales
    sale(30_000, currency: "PKR")
    described_class.call
    expect(guide.sales_count).to eq(5)
    expect(PriceGuide.find_by(category: phones, currency: "PKR")).to have_attributes(sales_count: 1, available: false)
  end

  it "skips Stays, Jobs, Services, Property and Other (rents, salaries, rates, mixed)" do
    stays = create(:category, kind: "stay")
    jobs  = create(:category, slug: "jobs")
    sub   = create(:category, parent: jobs)
    5.times { |i| sale(1000 + i, category: create(:category, parent: stays), seller: sellers[i % 3]) }
    5.times { |i| sale(1000 + i, category: sub, seller: sellers[i % 3]) }
    described_class.call
    expect(PriceGuide.where.not(category: phones)).to be_empty
  end

  it "rebuilds from scratch: a bucket whose sales aged out is removed" do
    five_sales
    described_class.call
    travel 100.days
    described_class.call
    expect(guide).to be_nil
  end
end
