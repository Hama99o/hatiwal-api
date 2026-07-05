require "swagger_helper"

RSpec.describe "Api::V1::My::TransactionsController", type: :request do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  # ── RSwag path ────────────────────────────────────────────────────────────────
  path "/api/v1/my/transactions" do
    get "list the caller's transactions (as buyer and/or seller)" do
      tags "Transactions"
      description <<~DESC
        Returns the current user's transactions — both the ones where they are
        the seller and the ones where they are the buyer. Optional `?as=buyer`
        or `?as=seller` narrows to a single role. TASK-TX01.
      DESC
      produces "application/json"

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false
      parameter name: :as, in: :query, type: :string, required: false,
                description: "Optional role filter: 'buyer' or 'seller'"

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        run_test! do |response|
          expect(response).to have_http_status(:unauthorized)
        end
      end

      response "200", "returns transactions where the caller is buyer or seller" do
        before do
          listing = create(:listing, :active, user: seller)
          create(:conversation, listing: listing, seller: seller, buyer: buyer)
          @as_seller = create(:transaction, listing: listing, seller: seller, buyer: buyer)

          other_listing = create(:listing, :active, user: create(:user))
          create(:conversation, listing: other_listing, seller: other_listing.user, buyer: seller)
          @as_buyer = create(:transaction, listing: other_listing, seller: other_listing.user, buyer: seller)

          # Unrelated transaction — must never appear.
          create(:transaction)
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          ids = data["transactions"].map { |t| t["id"] }
          expect(ids).to contain_exactly(@as_seller.id, @as_buyer.id)
          expect(data["meta"]["pagination"]).to have_key("total_count")
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "?as=seller narrows to transactions where the caller is the seller" do
        let(:as) { "seller" }

        before do
          listing = create(:listing, :active, user: seller)
          create(:conversation, listing: listing, seller: seller, buyer: buyer)
          @as_seller = create(:transaction, listing: listing, seller: seller, buyer: buyer)

          other_listing = create(:listing, :active, user: create(:user))
          create(:conversation, listing: other_listing, seller: other_listing.user, buyer: seller)
          create(:transaction, listing: other_listing, seller: other_listing.user, buyer: seller)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          ids = data["transactions"].map { |t| t["id"] }
          expect(ids).to eq([ @as_seller.id ])
          expect(data["transactions"].first["role"]).to eq("seller")
        end
      end
    end
  end

  # ── Functional specs ─────────────────────────────────────────────────────────

  describe "GET /api/v1/my/transactions" do
    it "requires authentication" do
      get "/api/v1/my/transactions", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "never returns another pair's transaction" do
      other_seller = create(:user)
      create(:transaction, seller: other_seller)

      get "/api/v1/my/transactions", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["transactions"]).to eq([])
    end

    it "includes listing/buyer/seller identity payload" do
      listing = create(:listing, :active, user: seller)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      create(:transaction, listing: listing, seller: seller, buyer: buyer, final_price: 5000)

      get "/api/v1/my/transactions", headers: headers, as: :json

      txn = JSON.parse(response.body)["transactions"].first
      expect(txn["listing"]["id"]).to eq(listing.id)
      expect(txn["buyer"]["id"]).to eq(buyer.id)
      expect(txn["seller"]["id"]).to eq(seller.id)
      expect(txn["final_price"].to_f).to eq(5000.0)
      expect(txn["role"]).to eq("seller")
    end
  end
end
