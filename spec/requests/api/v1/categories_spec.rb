require "rails_helper"

RSpec.describe "Api::V1::Categories", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/categories" do
    it "is public — guests can load categories without auth" do
      create(:category, position: 1, active: true)
      get "/api/v1/categories", as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns only top-level active categories ordered by position" do
      first  = create(:category, position: 1, active: true)
      second = create(:category, position: 2, active: true)
      # inactive should not appear
      create(:category, active: false)
      # subcategory should not appear at top level
      create(:category, parent: first, active: true)

      get "/api/v1/categories", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      ids  = body["categories"].map { |c| c["id"] }
      expect(ids).to eq([ first.id, second.id ])
    end

    it "each category has a subcategories key that is an Array" do
      create(:category, position: 1, active: true)

      get "/api/v1/categories", headers: headers, as: :json

      body     = JSON.parse(response.body)
      category = body["categories"].first
      expect(category).to have_key("subcategories")
      expect(category["subcategories"]).to be_an(Array)
    end

    it "a category without subcategories has an empty subcategories array" do
      create(:category, active: true)

      get "/api/v1/categories", headers: headers, as: :json

      body     = JSON.parse(response.body)
      category = body["categories"].first
      expect(category["subcategories"]).to eq([])
    end

    it "includes active subcategories nested under their parent" do
      parent    = create(:category, active: true)
      active_sub  = create(:category, parent: parent, active: true)
      inactive_sub = create(:category, parent: parent, active: false)

      get "/api/v1/categories", headers: headers, as: :json

      body = JSON.parse(response.body)
      cat  = body["categories"].find { |c| c["id"] == parent.id }
      sub_ids = cat["subcategories"].map { |s| s["id"] }

      expect(sub_ids).to include(active_sub.id)
      expect(sub_ids).not_to include(inactive_sub.id)
    end

    it "exposes all three locale names" do
      create(:category, name_en: "Electronics", name_ps: "بریښنایي", name_fa: "الکترونیک")

      get "/api/v1/categories", headers: headers, as: :json

      category = JSON.parse(response.body)["categories"].first
      expect(category).to include("name_en" => "Electronics", "name_ps" => "بریښنایي", "name_fa" => "الکترونیک")
    end

    it "subcategories also expose all three locale names" do
      parent = create(:category, active: true)
      create(:category, parent: parent, active: true,
             name_en: "Phones", name_ps: "موبایل", name_fa: "گوشی")

      get "/api/v1/categories", headers: headers, as: :json

      body   = JSON.parse(response.body)
      cat    = body["categories"].find { |c| c["id"] == parent.id }
      subcat = cat["subcategories"].first

      expect(subcat).to include("name_en" => "Phones", "name_ps" => "موبایل", "name_fa" => "گوشی")
    end
  end
end
