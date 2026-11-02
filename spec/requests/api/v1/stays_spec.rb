require "rails_helper"

# Stays end to end through the API (docs/STAYS_DESIGN.md): post a room, read it
# back with its unit + details + category kind, search by guests / amenities /
# unit — and the request the SHIPPED 1.1.6 app makes still works.
RSpec.describe "Stays", type: :request do
  let(:seller) { create(:user) }
  let(:headers) { auth_headers_for(seller) }
  let(:json_headers) { headers.merge("Content-Type" => "application/json", "Accept" => "application/json") }
  let!(:stays) { create(:category, slug: "stays", kind: Category::KIND_STAY) }
  let!(:rooms) { create(:category, slug: "hotel-rooms", parent: stays) }
  let!(:phones) { create(:category, slug: "phones") }

  def body = JSON.parse(response.body)

  describe "POST /api/v1/my/listings" do
    let(:room) do
      { title: "Double room, Shahr-e Naw", price: 1500, currency: "AFN", category_id: rooms.id, quantity: 3,
        location: "Kabul", latitude: 34.5553, longitude: 69.2075 }
    end

    it "creates a room priced per night with its details" do
      details = { guests: 2, beds: 1, bathroom: "private", amenities: %w[wifi hot_water breakfast], check_in: "14:00", check_out: "11:00" }
      post "/api/v1/my/listings", params: { listing: room.merge(details: details) }.to_json, headers: json_headers
      expect(response).to have_http_status(:created), response.body
      listing = body["listing"]
      expect(listing["price_unit"]).to eq("night")
      expect(listing["details"]).to eq("guests" => 2, "beds" => 1, "bathroom" => "private", "amenities" => %w[wifi hot_water breakfast], "check_in" => "14:00", "check_out" => "11:00")
      expect(listing["condition"]).to be_nil
    end

    it "takes the details from a multipart form too (the mobile app sends photos)" do
      post "/api/v1/my/listings", params: { listing: room.merge(details: { guests: "4", amenities: [ "wifi" ] }) }, headers: headers
      expect(response).to have_http_status(:created), response.body
      expect(body["listing"]["details"]).to eq("guests" => 4, "amenities" => [ "wifi" ])
    end

    it "refuses bad details with a 422 on details" do
      post "/api/v1/my/listings", params: { listing: room.merge(details: { guests: 0, bathroom: "ensuite" }) }.to_json, headers: json_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("guests must be", "bathroom must be")
    end

    it "keeps working for the shipped 1.1.6 app (no unit, no details, a condition): a room per night" do
      post "/api/v1/my/listings", params: { listing: room.merge(condition: "good") }.to_json, headers: json_headers
      expect(response).to have_http_status(:created), response.body
      expect(body["listing"]["price_unit"]).to eq("night")
      expect(body["listing"]["details"]).to eq({})
    end

    it "refuses a per-night price on an item" do
      post "/api/v1/my/listings", params: { listing: room.merge(category_id: phones.id, price_unit: "night") }.to_json, headers: json_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Price unit is not available")
    end
  end

  describe "GET /api/v1/listings (search)" do
    let!(:double) { create(:listing, :active, title: "Double", price: 1500, category: rooms, details: { "guests" => 2, "amenities" => %w[wifi breakfast] }) }
    let!(:family) { create(:listing, :active, title: "Family", price: 3000, category: rooms, details: { "guests" => 5, "amenities" => %w[wifi parking] }) }
    let!(:phone) { create(:listing, :active, title: "Phone", price: 2000, category: phones) }

    def titles = body["listings"].map { |l| l["title"] }

    it "lists stays under the Stays root, with unit, details and the category kind" do
      get "/api/v1/listings", params: { category_id: stays.id }
      expect(titles).to contain_exactly("Double", "Family")
      card = body["listings"].find { |l| l["title"] == "Double" }
      expect(card["price_unit"]).to eq("night")
      expect(card["details"]["guests"]).to eq(2)
      expect(card["category"]["kind"]).to eq("stay")
    end

    it "filters by guests, amenities and price unit, and ignores unreadable values" do
      get "/api/v1/listings", params: { guests: 3 }
      expect(titles).to contain_exactly("Family")
      get "/api/v1/listings", params: { amenities: %w[wifi breakfast] }
      expect(titles).to contain_exactly("Double")
      get "/api/v1/listings", params: { price_unit: "night", price_max: 2000 }
      expect(titles).to contain_exactly("Double")
      get "/api/v1/listings", params: { guests: "lots", amenities: [ "pool" ], price_unit: "week" }
      expect(titles).to contain_exactly("Double", "Family", "Phone")
    end

    it "gives items an empty details hash and no unit" do
      get "/api/v1/listings", params: { category_id: phones.id }
      expect(body["listings"].first.slice("price_unit", "details")).to eq("price_unit" => nil, "details" => {})
    end
  end

  describe "chats about a room" do
    it "carry the price unit in the inbox row and the thread header" do
      buyer = create(:user)
      room = create(:listing, :active, category: rooms, user: seller)
      conversation = create(:conversation, listing: room, buyer: buyer, seller: seller)
      buyer_headers = auth_headers_for(buyer)
      get "/api/v1/conversations", headers: buyer_headers
      expect(body["conversations"].first["listing"]["price_unit"]).to eq("night")
      get "/api/v1/conversations/#{conversation.id}", headers: buyer_headers
      expect(body["conversation"]["listing"]["price_unit"]).to eq("night")
    end
  end

  describe "GET /api/v1/categories" do
    it "carries the kind on roots and subcategories" do
      get "/api/v1/categories"
      root = body["categories"].find { |c| c["slug"] == "stays" }
      expect(root["kind"]).to eq("stay")
      expect(root["subcategories"].map { |c| c["kind"] }).to eq([ "stay" ])
      expect(body["categories"].find { |c| c["slug"] == "phones" }["kind"]).to eq("item")
    end
  end
end
