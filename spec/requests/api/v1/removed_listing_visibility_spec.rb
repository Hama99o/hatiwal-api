require "rails_helper"

# A listing taken down by an admin disappears for buyers but stays visible to
# its owner.
RSpec.describe "Removed listing visibility", type: :request do
  it "excludes removed listings from the public feed" do
    visible = create(:listing, :active)
    removed = create(:listing, :active)
    removed.take_down!

    get "/api/v1/listings", as: :json

    ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
    expect(ids).to include(visible.id)
    expect(ids).not_to include(removed.id)
  end

  it "returns 404 on a removed listing for a guest / non-owner" do
    removed = create(:listing, :active)
    removed.take_down!

    get "/api/v1/listings/#{removed.id}", as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "still lets the owner view their own removed listing" do
    owner = create(:user)
    removed = create(:listing, :active, user: owner)
    removed.take_down!

    get "/api/v1/listings/#{removed.id}", headers: auth_headers_for(owner), as: :json
    expect(response).to have_http_status(:ok)
  end
end
