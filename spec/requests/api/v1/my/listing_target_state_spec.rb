require "rails_helper"

# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.3) — status changes are TARGET
# states. The phone may send a "publish" or "mark sold" long after it was
# queued; if the listing is already there (the web, a teammate, or this same
# request's lost first answer), that is a success: 200 + `already: true`.
RSpec.describe "My listings — target-state status changes", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  def put_action(listing, action, body = {})
    put "/api/v1/my/listings/#{listing.id}/#{action}", params: body, headers: headers, as: :json
  end

  def body = JSON.parse(response.body)

  it "publish on a listing already live → 200 already, nothing changes" do
    listing = create(:listing, :active, user: seller)
    expect { put_action(listing, :publish) }.not_to(change { listing.reload.updated_at })
    expect(response).to have_http_status(:ok)
    expect(body["already"]).to be(true)
    expect(body["listing"]["status"]).to eq("active")
  end

  it "unpublish on a draft → 200 already" do
    listing = create(:listing, user: seller)
    put_action(listing, :unpublish)
    expect(response).to have_http_status(:ok)
    expect(body["already"]).to be(true)
  end

  it "mark sold on a listing already sold → 200 already, no second sale" do
    listing = create(:listing, :active, user: seller)
    put_action(listing, :sold)
    expect(response).to have_http_status(:ok)
    expect(listing.reload).to be_sold
    expect(body["already"]).to be_nil

    expect { put_action(listing, :sold) }.not_to change(Transaction, :count)
    expect(response).to have_http_status(:ok)
    expect(body["already"]).to be(true)
  end

  it "activate (release the hold) on a live listing with no hold → 200 already" do
    listing = create(:listing, :active, user: seller)
    put_action(listing, :activate)
    expect(response).to have_http_status(:ok)
    expect(body["already"]).to be(true)
  end

  it "a real change still answers without `already`" do
    listing = create(:listing, user: seller)
    listing.images.attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open, filename: "p.jpg", content_type: "image/jpeg")
    put_action(listing, :publish)
    expect(response).to have_http_status(:ok)
    expect(body).not_to have_key("already")
    expect(listing.reload).to be_active
  end

  it "someone who may not edit the listing learns nothing (404, as before)" do
    listing = create(:listing, :active)
    put_action(listing, :publish)
    expect(response).to have_http_status(:not_found)
  end

  it "a deleted listing is never answered 'already' (it takes the ordinary path)" do
    listing = create(:listing, :sold, user: seller, removed_at: Time.current)
    put_action(listing, :sold)
    expect(body["already"]).to be_nil
  end

  it "deleting an already-deleted listing → 204 (the retry of a lost answer)" do
    listing = create(:listing, :active, user: seller)
    delete "/api/v1/my/listings/#{listing.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    delete "/api/v1/my/listings/#{listing.id}", headers: headers
    expect(response).to have_http_status(:no_content)
  end

  # Coverage pass 2026-10-28: deleted on another device, then a queued publish
  # arrives. A deleted listing is never "already live": refuse_removed_listing
  # answers before the target-state check, and it stays deleted.
  it "publish on a listing the seller deleted meanwhile → refused, not `already`, still deleted" do
    listing = create(:listing, :active, user: seller, removed_at: Time.current, removed_reason: "deleted_by_seller")
    put_action(listing, :publish)
    expect(response).to have_http_status(:forbidden)
    expect(body).not_to have_key("already")
    expect(listing.reload.removed_at).to be_present
  end
end
