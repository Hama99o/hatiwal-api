require "rails_helper"

RSpec.describe "Api::V1::Categories", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/categories" do
    it "requires authentication" do
      get "/api/v1/categories", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns active categories ordered by position" do
      first  = create(:category, position: 1, active: true)
      second = create(:category, position: 2, active: true)
      create(:category, active: false)

      get "/api/v1/categories", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      ids  = body["categories"].map { |c| c["id"] }
      expect(ids).to eq([ first.id, second.id ])
    end

    it "exposes all three locale names" do
      create(:category, name_en: "Electronics", name_ps: "بریښنایي", name_fa: "الکترونیک")

      get "/api/v1/categories", headers: headers, as: :json

      category = JSON.parse(response.body)["categories"].first
      expect(category).to include("name_en" => "Electronics", "name_ps" => "بریښنایي", "name_fa" => "الکترونیک")
    end
  end
end
