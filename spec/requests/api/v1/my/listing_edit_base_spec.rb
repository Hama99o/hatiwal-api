require "rails_helper"

# OFFLINE phase 2a (docs/OFFLINE_MODE.md §7.2, §10.2, §10.5) — an edit carries
# the values the seller SAW (`base`). A field changed elsewhere meanwhile is not
# overwritten; the rest of the edit applies; the answer names the conflict.
RSpec.describe "My listings — edits with a base", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:seller)   { create(:user, firstname: "Ahmad", lastname: "Karimi") }
  let(:headers)  { auth_headers_for(seller) }
  let(:listing)  { create(:listing, :active, user: seller, title: "Bike", price: 500) }

  def edit(attrs, base: nil, as: headers)
    patch "/api/v1/my/listings/#{listing.id}", params: { listing: attrs.merge(base ? { base: base } : {}) }, headers: as, as: :json
  end

  def body = JSON.parse(response.body)

  it "nothing changed meanwhile: applied (200)" do
    edit({ price: 450 }, base: { price: 500 })
    expect(response).to have_http_status(:ok)
    expect(listing.reload.price).to eq(450)
  end

  it "someone already made the same change: done, no conflict (200)" do
    listing.update!(price: 450)
    edit({ price: 450 }, base: { price: 500 })
    expect(response).to have_http_status(:ok)
    expect(body).not_to have_key("code")
  end

  it "changed elsewhere: 409 edit_conflict for THAT field — yours, theirs, when, by whom — and the other fields still apply" do
    teammate_shop = create(:shop, owner: seller)
    teammate = create(:user, firstname: "Hamid", lastname: "Rahimi")
    teammate_shop.shop_members.create!(user: teammate, role: :staff)
    listing.update!(shop: teammate_shop)
    travel_to(Time.zone.parse("2026-10-26 14:02")) do
      listing.reload.tap { |l| l.acting_user = teammate }.update!(price: 480)
    end

    edit({ price: 450, title: "Blue bike" }, base: { price: 500, title: "Bike" })

    expect(response).to have_http_status(:conflict)
    expect(body["code"]).to eq("edit_conflict")
    price = body["fields"]["price"]
    expect([ price["yours"].to_f, price["theirs"].to_f ]).to eq([ 450.0, 480.0 ])
    # Money as JSON numbers (ad9af59), in a conflict too — never "480.0".
    expect(price["theirs"]).to be_a(Float)
    expect(price["changed_by_name"]).to eq("Hamid Rahimi")
    expect(Time.zone.parse(price["changed_at"])).to eq(Time.zone.parse("2026-10-26 14:02"))
    expect(body["fields"].keys).to eq([ "price" ])
    expect(listing.reload.title).to eq("Blue bike")
    expect(listing.price).to eq(480)
    expect(body["listing"]["title"]).to eq("Blue bike")
  end

  it "a sale or views meanwhile (sold_units, views_count) never conflict with an edit" do
    listing.update_columns(views_count: 99)
    listing.update!(quantity: 5)
    listing.update_columns(sold_units: 2)
    edit({ price: 450 }, base: { price: 500 })
    expect(response).to have_http_status(:ok)
  end

  it "without a base (every 1.1.x app): the edit overwrites, as before" do
    listing.update!(price: 480)
    edit({ price: 450 })
    expect(response).to have_http_status(:ok)
    expect(listing.reload.price).to eq(450)
    expect(body).not_to have_key("code")
  end

  it "remembers who changed which field (the seller, through the app)" do
    edit({ title: "Blue bike" })
    edit_stamp = listing.reload.field_edits["title"]
    expect(edit_stamp["by"]).to eq(seller.id)
    expect(listing.field_edits).not_to have_key("price")
  end

  # Coverage pass 2026-10-28.
  it "changed by the system (no person: an admin task, a job): the conflict names nobody, never a wrong name" do
    listing.update!(price: 480) # acting_user nil
    edit({ price: 450 }, base: { price: 500 })
    expect(response).to have_http_status(:conflict)
    expect(body["fields"]["price"]["changed_by_name"]).to be_nil
    expect(body["fields"]["price"]["changed_at"]).to be_present
  end

  it "an empty field the form sends as \"\" matches one stored as nil: no false conflict" do
    listing.update_columns(description: nil)
    edit({ description: "Red, 21 gears" }, base: { description: "" })
    expect(response).to have_http_status(:ok)
    expect(listing.reload.description).to eq("Red, 21 gears")
  end

  it "and the other way round: a field stored as \"\" (an older web edit) matches the app's empty (nil) base" do
    listing.update_columns(description: "")
    edit({ description: "Red, 21 gears" }, base: { description: nil })
    expect(response).to have_http_status(:ok)
    expect(listing.reload.description).to eq("Red, 21 gears")
  end
end
