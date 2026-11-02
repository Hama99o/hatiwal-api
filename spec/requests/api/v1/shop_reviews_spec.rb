require "swagger_helper"

# A shop's reviews (owner, 2026-10-06): only what BUYERS wrote about sales of
# THIS shop's products, each sale pinned to the shop when it was recorded.
# Never a review of the owner as a buyer, never the owner's personal sales.
RSpec.describe "Shop reviews", type: :request do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }

  def json = JSON.parse(response.body)

  # A sold sale of `listing` by the owner, reviewed by its buyer (visible).
  def reviewed_sale(listing, rating: 5)
    sale = create(:transaction, :sold, seller: owner, listing: listing)
    create(:review, :of_seller, :visible, sale: sale, rating: rating)
    sale
  end

  def shop_page = (get("/api/v1/shops/#{shop.id}") && json["shop"])

  path "/api/v1/shops/{shop_id}/reviews" do
    get "the shop's reviews (public)" do
      tags "Shops"
      description "Buyers' reviews of sales of this shop's products, newest first, paginated. A review of the owner " \
                  "as a buyer or of the owner's personal sales never appears. The shop page's avg_rating / " \
                  "review_count come from the same set. 404 for a closed shop."
      produces "application/json"
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :page, in: :query, type: :integer, required: false
      let(:shop_id) { shop.id }

      response "200", "the shop's reviews" do
        before { reviewed_sale(create(:listing, :active, user: owner, shop: shop), rating: 4) }

        run_test! do
          expect(json["reviews"].size).to eq(1)
          expect(json["reviews"].first).to include("rating" => 4)
        end
      end

      response "404", "a closed shop" do
        before { shop.close! }

        run_test!
      end
    end
  end

  it "a brand-new shop has no reviews, even when its owner has personal ones (buyer and seller)" do
    # The owner as a BUYER, reviewed by the person who sold to them.
    bought = create(:transaction, :sold, buyer: owner)
    create(:review, :visible, sale: bought, reviewee: owner)
    # The owner's PERSONAL sale, reviewed by its buyer.
    reviewed_sale(create(:listing, :active, user: owner))

    expect(shop_page).to include("review_count" => 0, "avg_rating" => nil)
    get "/api/v1/shops/#{shop.id}/reviews"
    expect(json["reviews"]).to eq([])
  end

  it "a shop sale's review counts, and stays after the product leaves the shop" do
    product = create(:listing, :active, user: owner, shop: shop)
    sale = reviewed_sale(product, rating: 4)
    expect(sale.shop_id).to eq(shop.id)
    expect(shop_page).to include("review_count" => 1, "avg_rating" => 4.0)

    shop.move_listings!(owner, [ product.id ], to_shop: false)
    expect(product.reload.shop_id).to be_nil
    expect(shop_page).to include("review_count" => 1)
  end

  it "a personal sale never counts, even if that product joins the shop later" do
    personal = create(:listing, :active, user: owner)
    reviewed_sale(personal)
    shop.move_listings!(owner, [ personal.id ], to_shop: true)
    expect(shop_page).to include("review_count" => 0)
  end

  it "a hidden (not yet revealed) review doesn't count; only the buyer's review of the sale does" do
    product = create(:listing, :active, user: owner, shop: shop)
    sale = create(:transaction, :sold, seller: owner, listing: product)
    create(:review, :of_seller, sale: sale)            # hidden
    create(:review, :visible, sale: sale)              # the SELLER's review of the buyer
    expect(shop_page).to include("review_count" => 0)
  end
end
