require "rails_helper"

# IDEA-6: the meetup sheet suggests spots near the listing, so the thread's
# listing carries its point — the grid-snapped one (SAFETY-1), never exact.
RSpec.describe "Conversation listing point", type: :request do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:listing) { create(:listing, :active, user: seller, latitude: 34.532441, longitude: 69.165663) }
  let(:conversation) { create(:conversation, listing: listing, buyer: buyer, seller: seller) }

  it "is the approximate point, as on the public listing" do
    get "/api/v1/conversations/#{conversation.id}", headers: auth_headers_for(buyer), as: :json
    point = response.parsed_body.dig("conversation", "listing").slice("latitude", "longitude")
    expect(point).to eq("latitude" => listing.approximate_latitude.to_f, "longitude" => listing.approximate_longitude.to_f)
    expect(point["latitude"]).not_to eq(34.532441)
  end
end
