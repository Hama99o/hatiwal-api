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
      parameter name: :listing_id, in: :query, type: :integer, required: false,
                description: "SF-B5 — narrow to one listing's ledger (the Sales screen)"
      parameter name: :status, in: :query, type: :string, required: false,
                description: "Optional status filter: 'reserved' or 'sold'"

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

      # SF-B5 — the Sales screen's read.
      response "200", "?listing_id= narrows to one listing's ledger" do
        let(:listing_id) { @listing.id }

        before do
          @listing = create(:listing, :active, user: seller, quantity: 5)
          create(:conversation, listing: @listing, seller: seller, buyer: buyer)
          @mine = create(:transaction, :sold, listing: @listing, seller: seller, buyer: buyer, quantity: 2)

          other = create(:listing, :active, user: seller)
          create(:conversation, listing: other, seller: seller, buyer: buyer)
          create(:transaction, :sold, listing: other, seller: seller, buyer: buyer)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["transactions"].map { |t| t["id"] }).to eq([ @mine.id ])
          expect(data["meta"]["pagination"]["total_count"]).to eq(1)
        end
      end
    end
  end

  # ── RSwag: the SF-B4 write endpoints ────────────────────────────────────────
  path "/api/v1/my/transactions/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true

    let(:listing) do
      l = create(:listing, :active, user: seller, quantity: 5, price: 1000)
      create(:conversation, listing: l, seller: seller, buyer: buyer)
      l
    end
    let(:sale) do
      txn = listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 5)
      listing.record_units_sold!(5)
      listing.sold!
      txn
    end
    let(:id) { sale.id }

    patch("correct a recorded sale") do
      tags "Transactions"
      description <<~DESC
        SF-B4 — edit a sale the seller already recorded: its quantity, its price,
        and/or who it was to. `quantity: 0` means "this sale did not happen" and
        is handled exactly like DELETE.

        Restores stock, moves the trust counters, and reconciles the listing's own
        status (a `sold` listing re-opens as `active` when the correction leaves
        units unsold). Refused with 422 + `code: "sale_has_review"` when the sale
        already has a review AND the change would void it or move its buyer.
      DESC
      consumes "application/json"
      produces "application/json"

      parameter name: :correction, in: :body, required: false, schema: {
        type: :object,
        properties: {
          quantity:    { type: :integer, description: "New unit count; 0 voids the sale" },
          buyer_id:    { type: :integer, description: "Reassign to another conversation participant" },
          clear_buyer: { type: :boolean, description: "Reassign to 'not on Hatiwal'" },
          final_price: { type: :number,  description: "Per-unit price actually agreed" }
        }
      }

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }
      let(:correction)     { { quantity: 1 } }

      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        run_test! { expect(response).to have_http_status(:unauthorized) }
      end

      response "200", "sale corrected; listing status and stock reconciled" do
        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["listing"]["status"]).to eq("active")
          expect(body["listing"]["available_units"]).to eq(4)
          expect(body["transaction"]["quantity"]).to eq(1)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end

      response "422", "the corrected quantity exceeds the listing's stock" do
        let(:correction) { { quantity: 99 } }
        run_test! do |response|
          expect(JSON.parse(response.body)["errors"]).to be_present
        end
      end
    end

    delete("void a recorded sale") do
      tags "Transactions"
      description <<~DESC
        SF-B4 — "Undo". Removes the sale, puts its units back in stock, gives back
        the seller's `sold_count` and the buyer's `bought_count` (never below
        zero), and re-opens the listing if this sale was what retired it.

        Refused with 422 + `code: "sale_has_review"` when the sale already has a
        review attached.
      DESC
      produces "application/json"

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        run_test! { expect(response).to have_http_status(:unauthorized) }
      end

      response "200", "sale removed, stock restored, listing re-opened" do
        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["listing"]["status"]).to eq("active")
          expect(body["listing"]["available_units"]).to eq(5)
          expect(body).not_to have_key("transaction")
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end

      response "422", "the sale already has a review" do
        before { create(:review, sale: sale, reviewer: seller, reviewee: buyer, role: :of_buyer) }

        run_test! do |response|
          expect(JSON.parse(response.body)["code"]).to eq("sale_has_review")
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

  # ── SF-B5 — the per-listing ledger read the Sales screen uses ──────────────
  describe "GET /api/v1/my/transactions?listing_id=" do
    let(:listing) do
      l = create(:listing, :active, user: seller, quantity: 10, price: 1000)
      create(:conversation, listing: l, seller: seller, buyer: buyer)
      l
    end

    it "returns only that listing's rows" do
      create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer, quantity: 3)

      other = create(:listing, :active, user: seller)
      create(:conversation, listing: other, seller: seller, buyer: buyer)
      create(:transaction, :sold, listing: other, seller: seller, buyer: buyer)

      get "/api/v1/my/transactions", params: { listing_id: listing.id, as: "seller", status: "sold" },
                                     headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      rows = JSON.parse(response.body)["transactions"]
      expect(rows.length).to eq(1)
      expect(rows.first["listing"]["id"]).to eq(listing.id)
      expect(rows.first["quantity"]).to eq(3)
    end

    it "returns one row per buyer, newest first, and paginates correctly" do
      buyer2 = create(:user)
      create(:conversation, listing: listing, seller: seller, buyer: buyer2)
      first  = create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer,
                                           quantity: 2, created_at: 2.hours.ago)
      second = create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer2,
                                           quantity: 3, created_at: 1.hour.ago)

      get "/api/v1/my/transactions", params: { listing_id: listing.id, as: "seller" },
                                     headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["transactions"].map { |t| t["id"] }).to eq([ second.id, first.id ])
      expect(body["meta"]["pagination"]["total_count"]).to eq(2)
    end

    it "excludes a still-reserved hold when ?status=sold is given" do
      create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer, quantity: 3)
      hold = create(:transaction, listing: listing, seller: seller, buyer: buyer, status: :reserved)

      get "/api/v1/my/transactions", params: { listing_id: listing.id, status: "sold" },
                                     headers: headers, as: :json

      ids = JSON.parse(response.body)["transactions"].map { |t| t["id"] }
      expect(ids).not_to include(hold.id)
    end

    it "ignores a nonsense status rather than 500ing" do
      create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)

      get "/api/v1/my/transactions", params: { listing_id: listing.id, status: "banana" },
                                     headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["transactions"].length).to eq(1)
    end

    it "never returns another seller's listing even when its id is asked for" do
      other_listing = create(:listing, :active, user: create(:user))
      create(:transaction, :sold, listing: other_listing, seller: other_listing.user, buyer: buyer)

      get "/api/v1/my/transactions", params: { listing_id: other_listing.id }, headers: headers, as: :json

      expect(JSON.parse(response.body)["transactions"]).to eq([])
    end
  end

  # ── SF-B5 — sales_count on the listing, so the seller learns there is more
  # than one buyer without opening the ledger screen. ────────────────────────
  describe "sales_count on ListingSerializer" do
    it "matches the number of sold rows in the ledger" do
      listing = create(:listing, :active, user: seller, quantity: 10, price: 1000)
      buyer2  = create(:user)
      [ buyer, buyer2 ].each { |b| create(:conversation, listing: listing, seller: seller, buyer: b) }

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer2.id, quantity: 3 }, headers: headers, as: :json

      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(JSON.parse(response.body)["listing"]["sales_count"]).to eq(2)

      get "/api/v1/my/transactions", params: { listing_id: listing.id, status: "sold" },
                                     headers: headers, as: :json
      expect(JSON.parse(response.body)["meta"]["pagination"]["total_count"]).to eq(2)
    end

    it "is 0 on a listing with no sales, and does not count an open hold" do
      listing = create(:listing, :active, user: seller, quantity: 5)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json

      expect(JSON.parse(response.body)["listing"]["sales_count"]).to eq(0)
    end

    it "is present on the public feed view too" do
      listing = create(:listing, :active, user: seller, quantity: 10)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json

      get "/api/v1/listings", as: :json

      row = JSON.parse(response.body)["listings"].find { |l| l["id"] == listing.id }
      expect(row["sales_count"]).to eq(1)
    end

    it "drops back when a sale is voided" do
      listing = create(:listing, :active, user: seller, quantity: 5)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json
      txn_id = JSON.parse(response.body)["transaction"]["id"]

      delete "/api/v1/my/transactions/#{txn_id}", headers: headers, as: :json

      expect(JSON.parse(response.body)["listing"]["sales_count"]).to eq(0)
    end
  end
end
