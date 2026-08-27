require "swagger_helper"

# SF-B7 — the three seller lifecycle actions that used to answer a validation
# failure with a 500 and an EMPTY BODY.
#
# `#renew`, `#activate` and `#unpublish` call bang writes (`renew!`, `active!`,
# `draft!`) and nothing rescued ActiveRecord::RecordInvalid — ApplicationController
# maps only Pundit::NotAuthorizedError, RecordNotFound and ParamError. So a
# listing that is invalid under a rule added AFTER it was created raised, and
# mobile's `apiErrorMessage` falls back to its generic "server error" string on
# exactly that shape: the seller was told nothing at all. #sold and #reserve have
# always rescued correctly; these three now match them.
#
# The invalid-legacy-row setup below is the real reproduction, not a contrivance:
# `latitude: 91` "was accepted and persisted" through POST /my/listings before
# Listing validated the coordinate range (see the note on that validation), and
# MAX_DESCRIPTION_LENGTH / MAX_IMAGES were both added after listings existed too.
# `update_column` is how we recreate such a row — it is the same bypass those
# listings came through (no validation), so the row is genuinely one of them.
RSpec.describe "Api::V1::My::Listings lifecycle errors (SF-B7)", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  # A listing that is live, owned by the seller, and invalid under a validation
  # introduced after it was written to the database.
  def legacy_invalid(status)
    listing = create(:listing, status, user: seller, expires_at: 2.days.ago)
    listing.update_column(:latitude, 91) # off the Earth — refused today, accepted then
    listing
  end

  # The assertion this whole ticket is about: a 422 the client can READ, never a
  # 500 with nothing in it.
  def expect_readable_422
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to be_present
    body = JSON.parse(response.body)
    expect(body["errors"]).to be_present
    expect(body["errors"].join(" ")).to include("Latitude")
    body
  end

  # ── RSwag ───────────────────────────────────────────────────────────────────
  # These three endpoints had no OpenAPI entry at all; documented here alongside
  # the 422 they can now answer with.
  %w[renew unpublish activate].each do |action|
    path "/api/v1/my/listings/{id}/#{action}" do
      parameter name: :id, in: :path, type: :integer, required: true

      put("#{action} one of the caller's own listings") do
        tags "Listings"
        description <<~DESC
          Seller lifecycle command. SF-B7 — a listing that fails validation
          (typically a legacy row that predates one of Listing's bounds) is
          answered with 422 and the field errors, never a 500 with an empty body.
        DESC
        produces "application/json"

        let(:"access-token") { headers["access-token"] }
        let(:client)         { headers["client"] }
        let(:uid)            { headers["uid"] }

        parameter name: :"access-token", in: :header, type: :string, required: false
        parameter name: :client,         in: :header, type: :string, required: false
        parameter name: :uid,            in: :header, type: :string, required: false

        # `activate` needs a reserved listing (ListingPolicy#activate?); the
        # other two need a live one.
        let(:starting_status) { action == "activate" ? :reserved : :active }
        let(:record)          { create(:listing, starting_status, user: seller, expires_at: 2.days.ago) }
        let(:id)              { record.id }

        response "401", "unauthorized" do
          let(:"access-token") { nil }
          run_test! { expect(response).to have_http_status(:unauthorized) }
        end

        response "200", "successful" do
          run_test! do |response|
            expect(JSON.parse(response.body)["listing"]).to be_present
          end

          after do |example|
            example.metadata[:response][:content] = {
              "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
            }
          end
        end

        response "422", "the listing fails validation" do
          let(:record) do
            listing = create(:listing, starting_status, user: seller, expires_at: 2.days.ago)
            listing.update_column(:latitude, 91)
            listing
          end

          run_test! do |response|
            expect(JSON.parse(response.body)["errors"]).to be_present
          end

          after do |example|
            example.metadata[:response][:content] = {
              "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
            }
          end
        end
      end
    end
  end

  # ── Functional specs ────────────────────────────────────────────────────────
  describe "PUT renew on a listing that is invalid under a later rule" do
    it "answers 422 with a field error, not a 500 with an empty body" do
      listing = legacy_invalid(:active)

      put "/api/v1/my/listings/#{listing.id}/renew", headers: headers, as: :json

      expect_readable_422
      expect(listing.reload.expires_at).to be < Time.current
    end
  end

  describe "PUT unpublish on a listing that is invalid under a later rule" do
    it "answers 422 with a field error, not a 500 with an empty body" do
      listing = legacy_invalid(:active)

      put "/api/v1/my/listings/#{listing.id}/unpublish", headers: headers, as: :json

      expect_readable_422
      expect(listing.reload.status).to eq("active")
    end

    it "rolls the cancelled hold back with the refused status flip" do
      buyer   = create(:user)
      listing = create(:listing, :active, user: seller, quantity: 1)
      create(:conversation, listing: listing, buyer: buyer)
      listing.reserve_with_buyer!(buyer_id: buyer.id)
      listing.reserved!
      listing.update_column(:latitude, 91)

      put "/api/v1/my/listings/#{listing.id}/unpublish", headers: headers, as: :json

      expect_readable_422
      # The rescue sits OUTSIDE the DB transaction, so `cancel_open_transaction!`
      # is rolled back — the buyer's hold survives an unpublish that failed.
      expect(listing.reload.open_transaction).to be_present
      expect(listing.status).to eq("reserved")
    end
  end

  describe "PUT activate on a listing that is invalid under a later rule" do
    it "answers 422 with a field error, not a 500 with an empty body" do
      listing = legacy_invalid(:reserved)

      put "/api/v1/my/listings/#{listing.id}/activate", headers: headers, as: :json

      expect_readable_422
      expect(listing.reload.status).to eq("reserved")
    end
  end

  describe "valid listings are untouched" do
    it "still renews, unpublishes and activates normally" do
      renewable = create(:listing, :active, user: seller, expires_at: 2.days.ago)
      put "/api/v1/my/listings/#{renewable.id}/renew", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(renewable.reload.expires_at).to be > Time.current

      live = create(:listing, :active, user: seller)
      put "/api/v1/my/listings/#{live.id}/unpublish", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(live.reload.status).to eq("draft")

      held = create(:listing, :reserved, user: seller)
      put "/api/v1/my/listings/#{held.id}/activate", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(held.reload.status).to eq("active")
    end
  end
end
