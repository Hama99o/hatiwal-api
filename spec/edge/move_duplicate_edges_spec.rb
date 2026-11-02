require "rails_helper"

# Edge-case pass, 2026-10-08 — Move to shop / Duplicate (owner items, 2026-10-12).
RSpec.describe "Move / Duplicate — edge cases", type: :request do
  let(:shop) { create(:shop) }
  let(:owner) { shop.owner }
  let(:manager) { create(:user, :confirmed) }
  let(:staff) { create(:user, :confirmed) }
  let(:other_shop) { create(:shop, owner: staff) } # staff owns a shop of their own

  before do
    shop.shop_members.create!(user: manager, role: :manager)
    shop.shop_members.create!(user: staff, role: :staff)
  end

  def move(listing, as:, to:)
    put "/api/v1/my/listings/#{listing.id}/move", headers: as.create_new_auth_token, params: { shop_id: to&.id }, as: :json
  end

  def duplicate(listing, as:, to:)
    post "/api/v1/my/listings/#{listing.id}/duplicate", headers: as.create_new_auth_token, params: { shop_id: to&.id }, as: :json
  end

  describe "a shop where you are Staff vs a manager" do
    let(:product) { create(:listing, :active, user: owner, shop: shop) }

    it "Staff cannot move the shop's product (posted by someone else) out, to Me or to their own shop" do
      move(product, as: staff, to: nil)
      expect(response).to have_http_status(:forbidden)
      move(product, as: staff, to: other_shop)
      expect(response).to have_http_status(:forbidden)
      expect(product.reload.shop_id).to eq(shop.id)
    end

    it "Staff cannot duplicate it out either, but may duplicate it inside the shop" do
      duplicate(product, as: staff, to: other_shop)
      expect(response).to have_http_status(:forbidden)
      duplicate(product, as: staff, to: shop)
      expect(response).to have_http_status(:created).or have_http_status(:ok)
    end

    it "a manager can move it to Me (it becomes theirs)" do
      move(product, as: manager, to: nil)
      expect(response).to have_http_status(:ok)
      expect(product.reload.attributes.slice("shop_id", "user_id")).to eq("shop_id" => nil, "user_id" => manager.id)
    end

    it "Staff can move THEIR OWN personal listing into the shop" do
      mine = create(:listing, :active, user: staff)
      move(mine, as: staff, to: shop)
      expect(response).to have_http_status(:ok)
      expect(mine.reload.shop_id).to eq(shop.id)
    end
  end

  describe "a listing with open chats" do
    let(:product) { create(:listing, :active, user: manager, shop: shop) }
    let(:buyer) { create(:user, :confirmed, preferred_language: "ps") }
    let!(:chat) do
      create(:conversation, listing: product, buyer: buyer, shop: shop).tap { |c| c.update_columns(seller_id: owner.id) }
    end

    it "each open chat gets one notice (in the buyer's language) and is closed; it stays with the old shop" do
      move(product, as: manager, to: nil)
      expect(response).to have_http_status(:ok)
      chat.reload
      expect(chat).to be_closed
      expect(chat.shop_id).to eq(shop.id)
      notices = chat.messages.where(kind: :system)
      expect(notices.count).to eq(1)
      expect(notices.first.context).to include("notice" => "listing_moved")
    end

    it "a held listing cannot move" do
      product.update_columns(status: Listing.statuses[:reserved])
      move(product, as: manager, to: nil)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(chat.reload).to be_open
    end
  end

  describe "duplicate" do
    let(:product) { create(:listing, :active, :with_image, user: owner, shop: shop) }

    it "with a photo whose file is gone: the draft still comes, without that photo" do
      product.images.attach(io: StringIO.new("x"), filename: "gone.jpg", content_type: "image/jpeg")
      gone = product.images.blobs.find_by(filename: "gone.jpg")
      ActiveStorage::Blob.service.delete(gone.key)
      duplicate(product, as: owner, to: shop)
      expect(response).to have_http_status(:created).or have_http_status(:ok)
      copy = Listing.order(:id).last
      expect(copy).to be_draft
      expect(copy.images.count).to eq(1)
    end

    it "a listing taken down by the admin cannot be duplicated back (nor one the seller deleted)" do
      product.take_down!(reason: "prohibited item")
      expect { duplicate(product, as: owner, to: shop) }.not_to change(Listing, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.to_s).to include("duplicate_removed")
    end

    it "a sold listing CAN be duplicated (\"sell another like this\")" do
      product.update_columns(status: Listing.statuses[:sold])
      duplicate(product, as: owner, to: shop)
      expect(response).to have_http_status(:created).or have_http_status(:ok)
    end

    it "into a closed shop is refused" do
      shop2 = create(:shop, owner: owner)
      shop2.close!
      duplicate(product, as: owner, to: shop2)
      expect(response.status).to be_between(400, 499)
    end
  end
end
