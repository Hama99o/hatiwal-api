require "rails_helper"

# d0 hunt 2026-10-09 (supervisor: critical, server-only, 1.1.6): an admin ban
# or suspension only set users.status. The seller's listings stayed in the
# feed, categories, search and detail, the public profile still served, and
# buyers could START chats with them — chats nobody can answer (the seller gets
# 403 everywhere, pushes to them are skipped). Existing chats stay readable.
RSpec.describe "A banned or suspended seller is unreachable for new buyers", type: :request do
  let(:buyer) { create(:user) }
  let(:seller) { create(:user) }
  let!(:listing) { create(:listing, :active, user: seller) }
  let!(:other) { create(:listing, :active) }
  def json = JSON.parse(response.body)

  %i[banned suspended].each do |state|
    context "seller #{state}" do
      before { seller.update_columns(status: User.statuses[state]) }

      it "is gone from the feed (guest and signed in)" do
        get "/api/v1/listings"
        expect(json["listings"].pluck("id")).to include(other.id)
        expect(json["listings"].pluck("id")).not_to include(listing.id)
        get "/api/v1/listings", headers: auth_headers_for(buyer)
        expect(json["listings"].pluck("id")).not_to include(listing.id)
      end

      it "their listing's detail is not found" do
        get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(buyer)
        expect(response).to have_http_status(:not_found)
      end

      it "their public profile is not found" do
        get "/api/v1/users/#{seller.id}/public_profile"
        expect(response).to have_http_status(:not_found)
        get "/api/v1/users/#{seller.id}", headers: auth_headers_for(buyer)
        expect(response).to have_http_status(:not_found)
      end

      it "a NEW chat is refused with the message the shipped apps already show ('not active')" do
        expect do
          post "/api/v1/listings/#{listing.id}/conversations",
               params: { message: "Still available?" }, headers: auth_headers_for(buyer), as: :json
        end.not_to change(Conversation, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]).to include("not active")
        expect(json["code"]).to be_nil # an uncoded 422 → the 1.1.6 apps say "no longer active"
      end

      it "a chat that already existed stays readable for the buyer" do
        seller.update_columns(status: User.statuses[:active])
        chat = Conversations::StartService.new(buyer: buyer, listing: listing, message_body: "Hi").call
        seller.update_columns(status: User.statuses[state])
        get "/api/v1/conversations/#{chat.id}/messages", headers: auth_headers_for(buyer)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  it "an active seller is unaffected" do
    get "/api/v1/listings"
    expect(json["listings"].pluck("id")).to include(listing.id)
    get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(buyer)
    expect(response).to have_http_status(:ok)
  end
end
