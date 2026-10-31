require "swagger_helper"

# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md §2): the keyword and the
# opt-in on saved searches, the per-search toggle, the 5-follow limit, and the
# account-wide switch.
RSpec.describe "Api::V1::Users::SavedSearches alerts", type: :request do
  let(:user)     { create(:user) }
  let(:headers)  { auth_headers_for(user) }
  let(:category) { create(:category) }

  let(:"access-token") { headers["access-token"] }
  let(:client)         { headers["client"] }
  let(:uid)            { headers["uid"] }

  path "/api/v1/users/saved_searches/{id}" do
    put "turn a saved search's alert on or off" do
      tags "Saved searches"
      description "Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md). `alert: true` follows the search: a new listing " \
                  "that matches it is pushed (batched per search every 6 h, at most 3 pushes a day, never 22:00–07:00 " \
                  "local). At most 5 followed searches; the 6th is 422 code alerts_limit. Owner only."
      consumes "application/json"
      produces "application/json"
      parameter name: :id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false
      parameter name: :body, in: :body, schema: { type: :object, properties: { alert: { type: :boolean } }, required: %w[alert] }

      response "200", "the search, with its alert state" do
        let(:search) { create(:saved_search, user: user, location: nil, category: category) }
        let(:id)     { search.id }
        let(:body)   { { alert: true } }

        run_test! do
          expect(response.parsed_body.dig("saved_search", "alert")).to be true
          expect(search.reload.alert).to be true
        end
      end

      response "422", "a 6th followed search (code alerts_limit)" do
        before { create_list(:saved_search, SavedSearch::MAX_ALERTS, user: user, alert: true) }

        let(:id)   { create(:saved_search, user: user).id }
        let(:body) { { alert: true } }

        run_test! { expect(response.parsed_body["code"]).to eq("alerts_limit") }
      end

      response "403", "someone else's search" do
        let(:id)   { create(:saved_search).id }
        let(:body) { { alert: true } }

        run_test!
      end
    end
  end

  it "saves the keyword and the opt-in in one request (the results banner)" do
    post "/api/v1/users/saved_searches", params: { category_id: category.id, query: "iphone", alert: true }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["saved_search"]).to include("query" => "iphone", "alert" => true)
  end

  it "lists followed searches even when they are older than the 4-chip history" do
    followed = create(:saved_search, user: user, alert: true, created_at: 10.days.ago)
    create_list(:saved_search, SavedSearch::MAX_PER_USER, user: user)

    get "/api/v1/users/saved_searches", headers: headers, as: :json
    ids = response.parsed_body["saved_searches"].map { |s| s["id"] }
    expect(ids).to include(followed.id)
    expect(ids.size).to eq(SavedSearch::MAX_PER_USER + 1)
  end

  it "turns every alert off (and back on) with one account switch" do
    put "/api/v1/users/me", params: { user: { saved_search_alerts: false } }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(user.reload.saved_search_alerts).to be false
  end
end
