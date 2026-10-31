require "rails_helper"

# IDEA-6: the admin keeps the meetup-spot list. A draft row says plainly that it
# still needs a local check, and stays hidden from the apps until switched on.
RSpec.describe "Admin meetup spots", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user) }
  let!(:draft) { create(:meetup_spot, name_en: "Shamshad Market", city_key: "jalalabad", active: false, needs_local_check: true) }

  it "is admin-only" do
    get admin_meetup_spots_path
    expect(response).to redirect_to(new_admin_user_session_path)
    sign_in create(:user), scope: :user
    get admin_meetup_spots_path
    expect(response).to redirect_to(new_admin_user_session_path)
  end

  describe "as an admin" do
    before { sign_in admin, scope: :admin_user }

    it "lists the spots, flags the ones that need a local check, and is in the menu" do
      create(:meetup_spot, name_en: "Majid Mall")
      get admin_meetup_spots_path
      expect(response.body).to include("Shamshad Market", "Majid Mall", "nav-meetup-spots", "needs-local-check-#{draft.id}")
      expect(response.body.scan(/needs-local-check-\d+/).size).to eq(1)
    end

    it "approves a draft row (local check done, switched on) and logs it" do
      patch admin_meetup_spot_path(draft), params: { meetup_spot: { needs_local_check: "0", active: "1" } }
      expect(draft.reload).to have_attributes(active: true, needs_local_check: false)
      expect(AdminAuditLog.find_by(action: "meetup_spot_update")).to have_attributes(target: draft, admin_user: admin)
    end

    it "adds a spot and logs it; a bad point is refused with a message" do
      post admin_meetup_spots_path, params: { meetup_spot: { city_key: "kandahar", name_en: "Ahmadi Market", kind: "mall",
                                                             latitude: "31.61305", longitude: "65.70350" } }
      created = MeetupSpot.find_by!(name_en: "Ahmadi Market")
      expect(response).to redirect_to(admin_meetup_spot_path(created))
      expect(AdminAuditLog.find_by(action: "meetup_spot_create")).to have_attributes(target: created)

      post admin_meetup_spots_path, params: { meetup_spot: { city_key: "kandahar", name_en: "Nowhere", kind: "mall", latitude: "200", longitude: "1" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "deletes a spot and logs it" do
      delete admin_meetup_spot_path(draft)
      expect(MeetupSpot.exists?(draft.id)).to be false
      expect(AdminAuditLog.find_by(action: "meetup_spot_destroy")).to be_present
    end
  end
end
