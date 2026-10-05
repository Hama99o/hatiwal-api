require "rails_helper"

# LOC-1 — the admin user page shows the own address and the guess side by side.
RSpec.describe "Admin user page — location panel", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, password: "changeme123!") }
  let(:user)  { create(:user, city: nil, province: nil) }

  before { sign_in admin, scope: :admin_user }

  it "shows the guess with its source when there is no own address" do
    user.record_location_guess!(latitude: 34.3529, longitude: 62.204, source: User::GuessSource::LISTING)
    get admin_user_path(user)
    expect(response).to have_http_status(:ok)
    panel = response.body[/<section id="user-location".*?<\/section>/m]
    expect(panel).to include("Guessed (learned by the app)", "Herat", "Listing", "guess")
  end

  it "says when the own address is abroad and not used" do
    user.update!(latitude: 25.2, longitude: 55.27)
    get admin_user_path(user)
    expect(response.body).to include("Outside the service area")
  end
end
