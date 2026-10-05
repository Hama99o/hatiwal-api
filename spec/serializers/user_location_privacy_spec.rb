require "rails_helper"

# LOC-1 — the guessed location is the app's private inference: it must never
# reach anyone but the user (hatiwal-mobile/docs/USER_LOCATION.md).
RSpec.describe "Guessed location privacy", type: :serializer do
  let(:user) { create(:user, city: nil, province: nil, show_address_publicly: true) }

  before { user.record_location_guess!(latitude: 34.3529, longitude: 62.204, source: User::GuessSource::LISTING) }

  %i[public minimal default].each do |view|
    it "is not in the user :#{view} view" do
      json = UserSerializer.render(user, view: view, current_user: create(:user))
      expect(json).not_to match(/guess|34\.3529|Herat/)
    end
  end

  it "is not in a listing's seller block" do
    listing = create(:listing, user: user, location: "Kabul", latitude: 34.5, longitude: 69.2)
    %i[list detailed].each do |view|
      json = ListingSerializer.render(listing, view: view, current_user: create(:user))
      expect(json).not_to match(/guess|34\.3529/)
    end
  end

  it "is only in :me, through the location block" do
    me = UserSerializer.render_as_hash(user, view: :me)
    expect(me.keys.grep(/guess/)).to be_empty
    expect(me[:location]).to include(source: "guess", province: "Herat")
  end
end
