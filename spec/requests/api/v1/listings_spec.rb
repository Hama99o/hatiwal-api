require "swagger_helper"

RSpec.describe "Api::V1::ListingsController", type: :request do
  path "/api/v1/listings" do
    get "browse active listings" do
      tags "Listings"
      description "Returns paginated active listings for buyers"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :search,         in: :query,  type: :string,  required: false
      parameter name: :category_id,    in: :query,  type: :integer, required: false

      let(:user)  { create(:user) }
      let(:headers) { auth_headers_for(user) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid)    { headers["uid"] }

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        let(:client) { nil }
        let(:uid)    { nil }

        run_test! do |response|
          expect(response).to have_http_status(:unauthorized)
        end
      end

      response "200", "successful" do
        before { create_list(:listing, 3, :active) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listings"]).to be_an(Array)
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
    end
  end

  path "/api/v1/listings/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "get a listing" do
      tags "Listings"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:user)    { create(:user) }
      let(:headers) { auth_headers_for(user) }
      let(:"access-token") { headers["access-token"] }
      let(:client)  { headers["client"] }
      let(:uid)     { headers["uid"] }
      let(:listing) { create(:listing, :active) }
      let(:id)      { listing.id }

      response "404", "not found" do
        let(:id) { 0 }
        run_test! do |response|
          expect(response).to have_http_status(:not_found)
        end
      end

      response "200", "successful" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["id"]).to eq(listing.id)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end
    end
  end
end
