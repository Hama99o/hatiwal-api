require "rails_helper"

# Owner, 2026-10-07: the Profile is personal. A person's sold_count, avg_rating
# and review_count leave out sales made as a shop (transactions.shop_id); those
# count only on the shop (Shop#reviews).
RSpec.describe "Personal trust stats exclude shop sales" do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }

  def personal_sale = create(:transaction, :sold, seller: owner, listing: create(:listing, :active, user: owner))
  def shop_sale = create(:transaction, :sold, seller: owner, listing: create(:listing, :active, user: owner, shop: shop))

  it "a personal sale counts on the person; a shop sale does not" do
    personal_sale
    sale = shop_sale
    expect(sale.shop_id).to eq(shop.id)
    expect(owner.reload.sold_count).to eq(1)
  end

  it "the buyer of a shop sale still counts it as bought (a person bought it)" do
    sale = shop_sale
    expect(sale.buyer.reload.bought_count).to eq(1)
  end

  it "voiding a shop sale leaves the owner's personal count alone" do
    personal_sale
    shop_sale.void!
    expect(owner.reload.sold_count).to eq(1)
  end

  it "the recompute (and the backfill migration) count personal sales only, idempotently" do
    personal_sale
    shop_sale
    owner.update_columns(sold_count: 7)
    2.times { owner.recompute_transaction_counters! }
    expect(owner.reload.sold_count).to eq(1)
  end

  it "a review of a shop sale rates the shop, not the owner; a personal one rates the owner" do
    create(:review, :of_seller, :visible, sale: shop_sale, rating: 2)
    create(:review, :of_seller, :visible, sale: personal_sale, rating: 5)
    owner.recompute_review_stats!

    expect(owner.reload).to have_attributes(review_count: 1, avg_rating: 5)
    expect(shop.reviews.count).to eq(1)
    expect(shop.review_stats).to eq([ 2.0, 1 ])
  end

  it "the shop's review OF its buyer stays on the buyer's profile" do
    sale = shop_sale
    create(:review, :visible, sale: sale, reviewer: owner, reviewee: sale.buyer, role: :of_buyer, rating: 4)
    sale.buyer.recompute_review_stats!
    expect(sale.buyer.reload.review_count).to eq(1)
  end
end

RSpec.describe "A user's public reviews list", type: :request do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }

  it "leaves out reviews of the owner's shop sales" do
    shop_sale = create(:transaction, :sold, seller: owner, listing: create(:listing, :active, user: owner, shop: shop))
    personal = create(:transaction, :sold, seller: owner, listing: create(:listing, :active, user: owner))
    create(:review, :of_seller, :visible, sale: shop_sale, rating: 2)
    mine = create(:review, :of_seller, :visible, sale: personal, rating: 5)

    get "/api/v1/users/#{owner.id}/reviews"
    expect(JSON.parse(response.body)["reviews"].pluck("id")).to eq([ mine.id ])
  end
end
