require "rails_helper"

# The seller's own listing search.
#
# The mobile app has always sent this: MyListings debounces its search field and
# passes `search:` to getMyListings, which appends ?search=. The controller
# dropped the parameter, so a seller typing into "Search my listings..." saw the
# full list unchanged — verified on a device, where the box held
# "QA Disposable lifecycle_reserve" while the header still read "18 listings".
#
# The public listings controller has applied Listing.search since it was written.
# These specs pin the seller side to the same behaviour, including the two things
# the scope is careful about: multi-word queries and LIKE metacharacters.
RSpec.describe "Api::V1::My::Listings search", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  let!(:bicycle) { create(:listing, :active, user: seller, title: "Mountain Bike 26-inch") }
  let!(:phone)   { create(:listing, :active, user: seller, title: "Samsung Galaxy S21") }

  def titles_from(response)
    JSON.parse(response.body).fetch("listings").map { |l| l["title"] }
  end

  it "returns only the matching listing" do
    get "/api/v1/my/listings", params: { search: "Mountain" }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(titles_from(response)).to eq([ bicycle.title ])
  end

  it "matches case-insensitively and on a substring" do
    get "/api/v1/my/listings", params: { search: "galaxy" }, headers: headers, as: :json

    expect(titles_from(response)).to eq([ phone.title ])
  end

  it "requires every word of a multi-word query to match" do
    get "/api/v1/my/listings", params: { search: "Mountain Galaxy" }, headers: headers, as: :json

    expect(titles_from(response)).to be_empty
  end

  it "treats a LIKE wildcard as a literal character, not a wildcard" do
    # Without escaping, "%" would match everything — the scope escapes it.
    get "/api/v1/my/listings", params: { search: "%" }, headers: headers, as: :json

    expect(titles_from(response)).to be_empty
  end

  it "returns everything when the search is blank" do
    get "/api/v1/my/listings", params: { search: "" }, headers: headers, as: :json

    expect(titles_from(response)).to contain_exactly(bicycle.title, phone.title)
  end

  it "combines with the status filter rather than replacing it" do
    create(:listing, user: seller, title: "Mountain Bike Draft", status: :draft)

    get "/api/v1/my/listings", params: { search: "Mountain", status: "active" },
        headers: headers, as: :json

    expect(titles_from(response)).to eq([ bicycle.title ])
  end
end
