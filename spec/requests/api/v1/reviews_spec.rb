require "swagger_helper"

RSpec.describe "Api::V1::Reviews", type: :request do
  let(:sale)    { create(:transaction, :sold) }
  let(:seller)  { sale.seller }
  let(:buyer)   { sale.buyer }
  let(:headers) { auth_headers_for(seller) }

  # ── POST /api/v1/transactions/:transaction_id/reviews ─────────────────────────
  path "/api/v1/transactions/{transaction_id}/reviews" do
    post "leave a review on a sold sale" do
      tags "Reviews"
      description <<~DESC
        The caller (a party to a SOLD transaction) rates the other party. The
        review is created hidden (double-blind) and revealed only once the
        counterparty also submits, or after the reveal window elapses.
      DESC
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :transaction_id, in: :path, type: :integer, required: true
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :review, in: :body, schema: {
        type: :object,
        properties: {
          review: {
            type: :object,
            properties: {
              rating:  { type: :integer, minimum: 1, maximum: 5 },
              comment: { type: :string }
            },
            required: %w[rating]
          }
        }
      }

      let(:transaction_id) { sale.id }
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }
      let(:review)         { { review: { rating: 5, comment: "Smooth deal" } } }

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }
        run_test! { |response| expect(response).to have_http_status(:unauthorized) }
      end

      response "201", "creates a hidden review" do
        run_test! do |response|
          expect(response).to have_http_status(:created)
          body = JSON.parse(response.body)["review"]
          expect(body["rating"]).to eq(5)
          expect(body["role"]).to eq("of_buyer")
          expect(body["visible"]).to be(false)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end

      response "403", "rejects a non-party" do
        let(:headers) { auth_headers_for(create(:user)) }
        run_test! { |response| expect(response).to have_http_status(:forbidden) }
      end
    end
  end

  # ── GET /api/v1/users/:user_id/reviews ────────────────────────────────────────
  path "/api/v1/users/{user_id}/reviews" do
    get "list a user's visible reviews" do
      tags "Reviews"
      description "Public, paginated list of the VISIBLE reviews a user has received. Optional ?role=of_seller|of_buyer."
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :user_id, in: :path, type: :integer, required: true
      parameter name: :role, in: :query, type: :string, required: false
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:user_id)        { seller.id }
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "200", "returns only visible reviews" do
        before do
          create(:review, :visible, :of_seller, sale: sale, rating: 4)
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["reviews"].size).to eq(1)
          expect(data["reviews"].first["rating"]).to eq(4)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end
    end
  end

  # ── Functional ────────────────────────────────────────────────────────────────
  describe "POST create" do
    it "reveals both reviews when the second party submits" do
      post "/api/v1/transactions/#{sale.id}/reviews",
           params: { review: { rating: 4 } }, headers: auth_headers_for(seller), as: :json
      post "/api/v1/transactions/#{sale.id}/reviews",
           params: { review: { rating: 5 } }, headers: auth_headers_for(buyer), as: :json

      expect(response).to have_http_status(:created)
      expect(Review.where(transaction_id: sale.id).pluck(:visible)).to all(be(true))
      expect(seller.reload.avg_rating.to_f).to eq(5.0)
      expect(buyer.reload.avg_rating.to_f).to eq(4.0)
    end

    it "rejects a duplicate review from the same party" do
      2.times do
        post "/api/v1/transactions/#{sale.id}/reviews",
             params: { review: { rating: 3 } }, headers: auth_headers_for(seller), as: :json
      end
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an out-of-range rating" do
      post "/api/v1/transactions/#{sale.id}/reviews",
           params: { review: { rating: 9 } }, headers: auth_headers_for(seller), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH update" do
    it "lets the author edit while hidden" do
      review = create(:review, reviewer: seller, reviewee: buyer, sale: sale, role: :of_buyer, rating: 3)
      patch "/api/v1/reviews/#{review.id}",
            params: { review: { rating: 5 } }, headers: auth_headers_for(seller), as: :json
      expect(response).to have_http_status(:ok)
      expect(review.reload.rating).to eq(5)
    end

    it "forbids editing once visible (locked)" do
      review = create(:review, :visible, reviewer: seller, reviewee: buyer, sale: sale, role: :of_buyer, rating: 3)
      patch "/api/v1/reviews/#{review.id}",
            params: { review: { rating: 5 } }, headers: auth_headers_for(seller), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET index" do
    it "hides reviews that are not yet revealed" do
      create(:review, :of_seller, sale: sale, rating: 2) # hidden
      get "/api/v1/users/#{seller.id}/reviews", headers: headers, as: :json
      expect(JSON.parse(response.body)["reviews"]).to eq([])
    end

    it "is readable by a guest (public trust surface)" do
      create(:review, :visible, :of_seller, sale: sale, rating: 5)
      get "/api/v1/users/#{seller.id}/reviews", as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["reviews"].first["rating"]).to eq(5)
    end

    it "does not leak reviews in a bare render json: literal" do
      controller_source = File.read(Rails.root.join("app/controllers/api/v1/reviews_controller.rb"))
      expect(controller_source).not_to include("render json:")
    end
  end
end
