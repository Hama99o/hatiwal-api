require "swagger_helper"

RSpec.describe "Api::V1::My::Reviews", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  path "/api/v1/my/reviews/pending" do
    get "sold sales the caller still owes a review on" do
      tags "Reviews"
      description "Returns the caller's SOLD transactions (as buyer or seller) that they have not yet reviewed. Drives the rating prompt."
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }
        run_test! { |response| expect(response).to have_http_status(:unauthorized) }
      end

      response "200", "lists unreviewed sold sales" do
        before do
          listing = create(:listing, :active, user: seller)
          buyer = create(:user)
          create(:conversation, listing: listing, seller: seller, buyer: buyer)
          @pending = create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)

          reviewed_listing = create(:listing, :active, user: seller)
          buyer2 = create(:user)
          create(:conversation, listing: reviewed_listing, seller: seller, buyer: buyer2)
          reviewed_sale = create(:transaction, :sold, listing: reviewed_listing, seller: seller, buyer: buyer2)
          create(:review, sale: reviewed_sale, reviewer: seller, reviewee: buyer2, role: :of_buyer)
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          ids = JSON.parse(response.body)["transactions"].map { |t| t["id"] }
          expect(ids).to eq([ @pending.id ])
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end
    end
  end

  describe "GET /api/v1/my/reviews/pending" do
    it "excludes reserved (not-yet-sold) transactions" do
      listing = create(:listing, :active, user: seller)
      buyer = create(:user)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      create(:transaction, listing: listing, seller: seller, buyer: buyer) # reserved

      get "/api/v1/my/reviews/pending", headers: headers, as: :json
      expect(JSON.parse(response.body)["transactions"]).to eq([])
    end
  end
end
