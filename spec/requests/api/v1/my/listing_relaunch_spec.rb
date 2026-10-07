require "swagger_helper"

# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 1): Renew is +90 days
# and never moves the listing; edit + relaunch (this endpoint, called after the
# edit is saved) renews AND may move it to the top, at most once a week.
RSpec.describe "Api::V1::My::Listings relaunch", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  path "/api/v1/my/listings/{id}/relaunch" do
    parameter name: :id, in: :path, type: :integer, required: true

    put("relaunch one of the caller's own listings (renew + weekly bump)") do
      tags "Listings"
      description <<~DESC
        Restarts the 90-day run (like renew), and moves the listing back to the
        top of the newest-first feed if it was last moved at least 7 days ago.
        `bumped` says whether this call moved it; `next_bump_at` when it next can
        (null = now). Photos, chats and the listing itself are kept.
      DESC
      produces "application/json"

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false

      let(:record) { create(:listing, :active, user: seller, created_at: 100.days.ago, expires_at: 10.days.ago) }
      let(:id)     { record.id }

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        run_test! { expect(response).to have_http_status(:unauthorized) }
      end

      response "403", "not the caller's listing, or not live" do
        let(:record) { create(:listing, :draft, user: seller) }
        run_test! { expect(response).to have_http_status(:forbidden) }
      end

      response "422", "the listing fails validation" do
        # A legacy row invalid under a later rule (see listing_lifecycle_errors_spec).
        let(:record) do
          create(:listing, :active, user: seller, expires_at: 2.days.ago).tap { |l| l.update_column(:latitude, 91) }
        end

        run_test! do |response|
          expect(JSON.parse(response.body)["errors"]).to be_present
          expect(record.reload.expires_at).to be < Time.current
        end
      end

      response "200", "successful" do
        run_test! do |response|
          body = JSON.parse(response.body)["listing"]
          expect(body["bumped"]).to be(true)
          expect(body["expired"]).to be(false)
          expect(body["next_bump_at"]).to be_present
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end
    end
  end

  describe "behaviour" do
    it "bumps at most once a week; the second relaunch still renews" do
      listing = create(:listing, :active, user: seller, created_at: 100.days.ago, expires_at: 10.days.ago)

      put "/api/v1/my/listings/#{listing.id}/relaunch", headers: headers, as: :json
      expect(JSON.parse(response.body)["listing"]["bumped"]).to be(true)
      first_bump = listing.reload.bumped_at

      travel 2.days do
        put "/api/v1/my/listings/#{listing.id}/relaunch", headers: headers, as: :json
        body = JSON.parse(response.body)["listing"]
        expect(response).to have_http_status(:ok)
        expect(body["bumped"]).to be(false)
        expect(Time.zone.parse(body["next_bump_at"])).to be_within(1.second).of(first_bump + 7.days)
        expect(listing.reload.bumped_at).to eq(first_bump)
        expect(listing.expires_at).to be_within(5.seconds).of(90.days.from_now)
      end
    end

    it "cannot reach another seller's listing" do
      other = create(:listing, :active, expires_at: 2.days.ago)
      put "/api/v1/my/listings/#{other.id}/relaunch", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(other.reload.expires_at).to be < Time.current
    end

    it "PUT renew gives 90 days and does not move the listing" do
      listing = create(:listing, :active, user: seller, created_at: 100.days.ago, expires_at: 2.days.ago)
      bumped_at = listing.bumped_at

      put "/api/v1/my/listings/#{listing.id}/renew", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.expires_at).to be_within(5.seconds).of(90.days.from_now)
      expect(listing.bumped_at).to eq(bumped_at)
      expect(JSON.parse(response.body)["listing"]["bumped"]).to be_nil
    end
  end
end
