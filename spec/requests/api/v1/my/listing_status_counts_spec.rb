require "rails_helper"

RSpec.describe "Api::V1::My::ListingStatusCounts", type: :request do
  let(:user)     { create(:user) }
  let(:other)    { create(:user) }
  let(:headers)  { auth_headers_for(user) }
  let(:category) { create(:category) }

  describe "GET /api/v1/my/listings/status_counts" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/v1/my/listings/status_counts", as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before do
        # Create listings for the current user in various statuses.
        create(:listing, :draft,    user: user, category: category)
        create(:listing, :active,   user: user, category: category, expires_at: 10.days.from_now)
        create(:listing, :active,   user: user, category: category, expires_at: 10.days.from_now)
        create(:listing, :active,   user: user, category: category, expires_at: 2.days.ago)   # expired
        create(:listing, :reserved, user: user, category: category)
        create(:listing, :sold,     user: user, category: category)
        create(:listing, :sold,     user: user, category: category)

        # Another user's listings — must NOT appear in the counts.
        create(:listing, :draft,  user: other, category: category)
        create(:listing, :active, user: other, category: category)
        create(:listing, :sold,   user: other, category: category)
      end

      it "returns 200 with per-status counts only for the current user" do
        get "/api/v1/my/listings/status_counts", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)

        expect(body["all"]).to eq(7)
        expect(body["draft"]).to eq(1)
        expect(body["reserved"]).to eq(1)
        expect(body["sold"]).to eq(2)
      end

      # SF-B1 — the "Active" tab is `live.not_expired` (active + reserved), so the
      # badge must count reserved rows too: 2 non-expired active + 1 reserved.
      # A badge that reads 2 over a list of 3 is the drift TASK-B903 fixed once
      # already on the public profile.
      it "active count includes reserved listings and excludes expired-active ones" do
        get "/api/v1/my/listings/status_counts", headers: headers, as: :json
        body = JSON.parse(response.body)

        expect(body["active"]).to eq(3)
      end

      it "the active badge equals what the widened Active tab actually returns" do
        get "/api/v1/my/listings/status_counts", headers: headers, as: :json
        badge = JSON.parse(response.body)["active"]

        get "/api/v1/my/listings", params: { status: "active" }, headers: headers, as: :json
        rows = JSON.parse(response.body)["listings"].length

        expect(badge).to eq(rows)
      end

      it "expired count equals the number of active listings past their expiry" do
        get "/api/v1/my/listings/status_counts", headers: headers, as: :json
        body = JSON.parse(response.body)

        expect(body["expired"]).to eq(1)
      end

      it "all count matches total (including expired-active, excluding other users)" do
        get "/api/v1/my/listings/status_counts", headers: headers, as: :json
        body = JSON.parse(response.body)

        expect(body["all"]).to eq(7)
      end

      it "returns zero for buckets with no listings" do
        user2    = create(:user)
        headers2 = auth_headers_for(user2)

        get "/api/v1/my/listings/status_counts", headers: headers2, as: :json
        body = JSON.parse(response.body)

        expect(body["all"]).to eq(0)
        expect(body["draft"]).to eq(0)
        expect(body["active"]).to eq(0)
        expect(body["expired"]).to eq(0)
        expect(body["reserved"]).to eq(0)
        expect(body["sold"]).to eq(0)
      end

      it "excludes removed (soft-deleted) listings from all counts" do
        create(:listing, :active, user: user, category: category, removed_at: 1.day.ago)

        get "/api/v1/my/listings/status_counts", headers: headers, as: :json
        body = JSON.parse(response.body)

        # The removed listing should not increment any bucket.
        expect(body["all"]).to eq(7)
      end
    end
  end
end
