require "rails_helper"

# A right-to-left name inside an English admin line ("Show …", tab <title>)
# must be isolated, or it fragments around Latin characters.
RSpec.describe "Admin display names are bidi-isolated" do
  it "wraps listing titles, user names and admin names in first-strong isolate marks" do
    listing = build(:listing, title: "د ۳x۴ میز")
    user = build(:user, firstname: "زرمینه", lastname: "خان")
    admin = build(:admin_user)

    [ ListingDashboard.new.display_resource(listing),
      UserDashboard.new.display_resource(user),
      AdminUserDashboard.new.display_resource(admin) ].each do |name|
      expect(name).to start_with(BidiIsolate::FSI).and end_with(BidiIsolate::PDI)
    end
    expect(ListingDashboard.new.display_resource(listing)).to eq("⁨د ۳x۴ میز⁩")
  end
end
