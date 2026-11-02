require "rails_helper"

# Authorization / IDOR sweep of 1.1.7 (2026-10-13). Each block is a gap that was
# reproduced live against the QA API with two real accounts before it was fixed.
RSpec.describe "1.1.7 IDOR sweep", type: :request do
  include ActionCable::TestHelper

  def json = JSON.parse(response.body)

  # "Unpublish: It will be hidden from buyers and moved back to draft." A draft
  # (never published, or taken offline) opened by id for a guest or any other
  # user: title, description, photos, price, seller card.
  describe "a draft listing is its seller's only" do
    let(:seller)   { create(:user) }
    let(:stranger) { create(:user) }
    let!(:draft)   { create(:listing, user: seller, title: "Unannounced phone") }

    it "is not found for a guest" do
      get "/api/v1/listings/#{draft.id}"
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Unannounced phone")
    end

    it "is not found for another signed-in user" do
      get "/api/v1/listings/#{draft.id}", headers: auth_headers_for(stranger)
      expect(response).to have_http_status(:not_found)
    end

    it "cannot be saved or offered as 'similar' by another user" do
      headers = auth_headers_for(stranger)
      post "/api/v1/listings/#{draft.id}/save", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(stranger.saved_listings).to be_empty
      get "/api/v1/listings/#{draft.id}/similar", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "drops out of Saved once it is taken offline (the card would not open)" do
      draft.update_columns(status: Listing.statuses[:active], expires_at: 30.days.from_now)
      stranger.saved_listings.create!(listing: draft)
      draft.update_columns(status: Listing.statuses[:draft])
      get "/api/v1/my/saved_listings", headers: auth_headers_for(stranger)
      expect(json["listings"]).to be_empty
    end

    it "cannot be reported (the report list echoes its title)" do
      post "/api/v1/reports", params: { report: { reportable_type: "Listing", reportable_id: draft.id, reason: "spam" } },
                              headers: auth_headers_for(stranger)
      expect(response).to have_http_status(:forbidden)
      expect(Report.where(reportable: draft)).to be_empty
    end

    it "still opens for its seller" do
      get "/api/v1/listings/#{draft.id}", headers: auth_headers_for(seller)
      expect(response).to have_http_status(:ok)
      expect(json["listing"]["title"]).to eq("Unannounced phone")
    end

    it "still opens for a member of its shop" do
      shop = create(:shop, owner: seller)
      draft.update!(shop: shop)
      staff = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
      get "/api/v1/listings/#{draft.id}", headers: auth_headers_for(staff)
      expect(response).to have_http_status(:ok)
    end

    it "an active listing is unchanged for a guest" do
      draft.update_columns(status: Listing.statuses[:active], expires_at: 30.days.from_now)
      get "/api/v1/listings/#{draft.id}"
      expect(response).to have_http_status(:ok)
    end
  end

  # SHOP-3: a member removed from (or leaving) a shop must stop seeing the shop's
  # ledger and its chats.
  describe "a member who left the shop" do
    let(:owner)  { create(:user) }
    let(:shop)   { create(:shop, owner: owner) }
    let(:staff)  { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
    let(:buyer)  { create(:user) }
    let(:product) { create(:listing, :active, user: staff, shop: shop) }
    let!(:sale) do
      Conversations::StartService.new(buyer: buyer, listing: product, message_body: "Salaam").call
      product.acting_user = staff
      product.sold_with_buyer!(buyer_id: buyer.id, final_price: product.price)
    end

    it "the sale is pinned to the shop and recorded by the staff member" do
      expect(sale).to have_attributes(shop_id: shop.id, recorded_by_id: staff.id, seller_id: owner.id)
    end

    it "no longer lists the shop's sales they recorded" do
      get "/api/v1/my/transactions", headers: auth_headers_for(staff)
      expect(json["transactions"].pluck("id")).to eq([ sale.id ])

      shop.remove_team_member!(staff, by: owner)
      get "/api/v1/my/transactions", headers: auth_headers_for(staff)
      expect(json["transactions"]).to be_empty
    end

    it "a personal sale they recorded themselves is still theirs" do
      own = create(:listing, :active, user: staff)
      Conversations::StartService.new(buyer: buyer, listing: own, message_body: "Hi").call
      own.acting_user = staff
      mine = own.sold_with_buyer!(buyer_id: buyer.id, final_price: own.price)
      shop.remove_team_member!(staff, by: owner)
      get "/api/v1/my/transactions", headers: auth_headers_for(staff)
      expect(json["transactions"].pluck("id")).to eq([ mine.id ])
    end

    # Live (QA 2026-10-13): a staff member subscribed to a shop chat kept
    # receiving the buyer's new messages over Action Cable after the owner
    # removed them; the subscription is only checked when it is made.
    it "is disconnected from Action Cable when removed, so the shop chats stop streaming" do
      expect { shop.remove_team_member!(staff, by: owner) }
        .to have_broadcasted_to("action_cable/#{staff.to_gid_param}").with(type: "disconnect", reconnect: true)
    end

    it "is disconnected when they leave too" do
      expect { shop.leave!(staff) }
        .to have_broadcasted_to("action_cable/#{staff.to_gid_param}").with(type: "disconnect", reconnect: true)
    end
  end

  # An offer / meetup reply must point at the message it answers. Without
  # `responds_to_id` the "other side" check never ran: a buyer could post a
  # bare "offer_accepted" / "offer_counter" / "meetup_accepted" bubble.
  describe "reply kinds answer a message" do
    let(:seller) { create(:user) }
    let(:buyer)  { create(:user) }
    let(:listing) { create(:listing, :active, user: seller) }
    let!(:chat) { Conversations::StartService.new(buyer: buyer, listing: listing, message_body: "Salaam").call }

    %w[offer_accepted offer_declined offer_counter meetup_accepted meetup_declined].each do |kind|
      it "#{kind} without responds_to_id is refused" do
        post "/api/v1/conversations/#{chat.id}/messages",
             params: { kind: kind, body: "500|AFN|1000" }, headers: auth_headers_for(buyer)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(chat.messages.where(kind: kind)).to be_empty
      end
    end

    it "a counter to the other side's offer still goes through" do
      offer = chat.messages.create!(user: buyer, kind: :offer, body: "800|AFN|1000")
      post "/api/v1/conversations/#{chat.id}/messages",
           params: { kind: "offer_counter", body: "900|AFN|1000", responds_to_id: offer.id }, headers: auth_headers_for(seller)
      expect(response).to have_http_status(:created)
    end
  end

  # A retracted message's text stays in the DB (soft delete); inbox search must
  # not find a chat by it, or the other side can confirm what was deleted.
  describe "conversation search" do
    let(:seller) { create(:user) }
    let(:buyer)  { create(:user) }
    let(:listing) { create(:listing, :active, user: seller, title: "Lamp") }
    let!(:chat) { Conversations::StartService.new(buyer: buyer, listing: listing, message_body: "Salaam").call }

    it "does not match a deleted message's text" do
      chat.messages.create!(user: buyer, kind: :text, body: "my number is zebrasecret42").soft_delete!
      get "/api/v1/conversations", params: { search: "zebrasecret42" }, headers: auth_headers_for(seller)
      expect(json["conversations"]).to be_empty

      chat.messages.create!(user: buyer, kind: :text, body: "zebrasecret42 again")
      get "/api/v1/conversations", params: { search: "zebrasecret42" }, headers: auth_headers_for(seller)
      expect(json["conversations"].pluck("id")).to eq([ chat.id ])
    end
  end
end
