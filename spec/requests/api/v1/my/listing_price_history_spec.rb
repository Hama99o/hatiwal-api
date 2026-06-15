require "rails_helper"

RSpec.describe "Api::V1::My::Listings — price history", type: :request do
  let(:user)     { create(:user) }
  let(:headers)  { auth_headers_for(user) }
  let(:category) { create(:category) }

  let!(:listing) do
    create(:listing, :active,
           user:     user,
           category: category,
           price:    10_000.00,
           currency: "AFN")
  end

  describe "PUT /api/v1/my/listings/:id" do
    context "when the price changes" do
      it "creates a ListingPriceHistory record" do
        expect do
          put "/api/v1/my/listings/#{listing.id}",
              params: { listing: { price: 8_000 } },
              headers: headers,
              as: :json
        end.to change { ListingPriceHistory.count }.by(1)
      end

      it "stores old_price and new_price correctly" do
        put "/api/v1/my/listings/#{listing.id}",
            params: { listing: { price: 7_500 } },
            headers: headers,
            as: :json

        history = listing.price_histories.last
        expect(history.old_price).to eq(10_000)
        expect(history.new_price).to eq(7_500)
      end

      it "returns price_dropped_at and price_drop_percent in the response" do
        put "/api/v1/my/listings/#{listing.id}",
            params: { listing: { price: 8_000 } },
            headers: headers,
            as: :json

        data = JSON.parse(response.body)["listing"]
        expect(data["price_dropped_at"]).to be_a(String)
        expect(data["price_drop_percent"]).to eq(20)
      end
    end

    context "when the price does not change" do
      it "does not create a ListingPriceHistory record" do
        expect do
          put "/api/v1/my/listings/#{listing.id}",
              params: { listing: { title: "Updated title" } },
              headers: headers,
              as: :json
        end.not_to change { ListingPriceHistory.count }
      end
    end

    context "when the price is increased (not a drop)" do
      it "still records the change in history but price_drop_percent is nil" do
        listing.update_column(:price, 5_000) # make sure 10_000 is an increase

        put "/api/v1/my/listings/#{listing.id}",
            params: { listing: { price: 10_000 } },
            headers: headers,
            as: :json

        data = JSON.parse(response.body)["listing"]
        # price_drop_percent should be nil because new > old
        expect(data["price_drop_percent"]).to be_nil
      end
    end
  end

  describe "GET /api/v1/listings (:list view) — price drop in browse feed" do
    context "when a recent price drop exists on a listing" do
      before do
        create(:listing_price_history, :recent_drop, listing: listing)
      end

      it "includes price_drop_percent in the browse feed response" do
        get "/api/v1/listings", headers: headers, as: :json

        data = JSON.parse(response.body)["listings"]
        item = data.find { |l| l["id"] == listing.id }
        expect(item).not_to be_nil
        expect(item["price_drop_percent"]).to be_an(Integer)
        expect(item["price_drop_percent"]).to be > 0
      end

      it "includes price_dropped_at in the browse feed response" do
        get "/api/v1/listings", headers: headers, as: :json

        data = JSON.parse(response.body)["listings"]
        item = data.find { |l| l["id"] == listing.id }
        expect(item["price_dropped_at"]).to be_a(String)
      end
    end

    context "when no recent price drop exists" do
      it "returns price_drop_percent as nil for a listing in the browse feed" do
        get "/api/v1/listings", headers: headers, as: :json

        data = JSON.parse(response.body)["listings"]
        item = data.find { |l| l["id"] == listing.id }
        expect(item).not_to be_nil
        expect(item["price_drop_percent"]).to be_nil
      end
    end
  end

  describe "GET /api/v1/my/listings (:seller_list view) — price drop in seller feed" do
    context "when a recent price drop exists on a listing" do
      before do
        create(:listing_price_history, :recent_drop, listing: listing)
      end

      it "includes price_drop_percent in the seller listing feed" do
        get "/api/v1/my/listings", headers: headers, as: :json

        data = JSON.parse(response.body)["listings"]
        item = data.find { |l| l["id"] == listing.id }
        expect(item).not_to be_nil
        expect(item["price_drop_percent"]).to be_an(Integer)
        expect(item["price_drop_percent"]).to be > 0
      end
    end

    context "when no recent price drop exists" do
      it "returns price_drop_percent as nil in the seller listing feed" do
        get "/api/v1/my/listings", headers: headers, as: :json

        data = JSON.parse(response.body)["listings"]
        item = data.find { |l| l["id"] == listing.id }
        expect(item).not_to be_nil
        expect(item["price_drop_percent"]).to be_nil
      end
    end
  end

  describe "GET /api/v1/listings/:id (:detailed view)" do
    context "when a recent price drop exists" do
      before do
        create(:listing_price_history, :recent_drop, listing: listing)
      end

      it "returns price_dropped_at in the response" do
        get "/api/v1/listings/#{listing.id}", headers: headers, as: :json

        data = JSON.parse(response.body)["listing"]
        expect(data["price_dropped_at"]).to be_a(String)
      end

      it "returns price_drop_percent in the response" do
        get "/api/v1/listings/#{listing.id}", headers: headers, as: :json

        data = JSON.parse(response.body)["listing"]
        expect(data["price_drop_percent"]).to be_an(Integer)
        expect(data["price_drop_percent"]).to be > 0
      end
    end

    context "when no price drop exists" do
      it "returns price_dropped_at as nil" do
        get "/api/v1/listings/#{listing.id}", headers: headers, as: :json

        data = JSON.parse(response.body)["listing"]
        expect(data["price_dropped_at"]).to be_nil
      end

      it "returns price_drop_percent as nil" do
        get "/api/v1/listings/#{listing.id}", headers: headers, as: :json

        data = JSON.parse(response.body)["listing"]
        expect(data["price_drop_percent"]).to be_nil
      end
    end

    context "when a price drop is older than 14 days" do
      before do
        create(:listing_price_history, :old_drop, listing: listing)
      end

      it "returns price_dropped_at as nil" do
        get "/api/v1/listings/#{listing.id}", headers: headers, as: :json

        data = JSON.parse(response.body)["listing"]
        expect(data["price_dropped_at"]).to be_nil
      end
    end
  end
end
