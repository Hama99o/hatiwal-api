require "rails_helper"

# In-app account deletion with a 30-day grace period (App Store 5.1.1(v) /
# Google Play). DELETE /api/v1/auth SCHEDULES deletion: the account is hidden
# and logged out immediately, but recoverable by logging back in and calling
# restore. FinalizeAccountDeletionsJob permanently anonymizes it after the grace
# window, retaining messages as "Deleted user" and freeing the email.
RSpec.describe "Api::V1::Auth account self-deletion (30-day grace)", type: :request do
  let(:user) do
    create(:user, firstname: "Sara", lastname: "Ahmadi",
                  phone: "0700000000", bio: "hello", city: "Kabul",
                  push_token: "ExponentPushToken[x]")
  end
  let(:headers) { auth_headers_for(user) }

  describe "DELETE /api/v1/auth (schedule)" do
    it "schedules deletion without destroying or anonymizing the record yet" do
      user

      expect do
        delete "/api/v1/auth", headers: headers, as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.deletion_scheduled_at).to be_present
      expect(user.deleted_at).to be_nil
      expect(user.full_name).to eq("Sara Ahmadi") # PII intact during the grace window
      expect(user.pending_deletion?).to be(true)
      expect(user.tokens).to eq({})               # all sessions ended
    end

    it "pulls the user's active listings from the feed (kept so restore can bring them back)" do
      listing = create(:listing, :active, user: user)
      delete "/api/v1/auth", headers: headers, as: :json
      expect(listing.reload.removed_at).to be_present
      expect(listing.removed_reason).to eq("pending_deletion")
    end

    it "does nothing without authentication" do
      user
      delete "/api/v1/auth", as: :json
      expect(user.reload.deletion_scheduled_at).to be_nil
    end
  end

  describe "while pending deletion" do
    before { delete "/api/v1/auth", headers: headers, as: :json }

    it "hides the public profile (404)" do
      get "/api/v1/users/#{user.id}", headers: auth_headers_for(create(:user)), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "still allows the user to log in so they can restore" do
      expect(user.reload.active_for_authentication?).to be(true)
    end
  end

  describe "POST /api/v1/users/me/restore (cancel within grace)" do
    it "restores the account and its pulled listings" do
      listing = create(:listing, :active, user: user)
      delete "/api/v1/auth", headers: headers, as: :json

      post "/api/v1/users/me/restore", headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.pending_deletion?).to be(false)
      expect(user.deletion_scheduled_at).to be_nil
      expect(listing.reload.removed_at).to be_nil
    end

    it "422s when the account is not scheduled for deletion" do
      post "/api/v1/users/me/restore", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "FinalizeAccountDeletionsJob" do
    it "anonymizes accounts past the grace window (PII stripped, login blocked, messages kept)" do
      listing = create(:listing, :active, user: user)
      buyer   = create(:user)
      convo   = create(:conversation, buyer: buyer, listing: listing)
      msg     = create(:message, conversation: convo, user: user, body: "Salaam")

      delete "/api/v1/auth", headers: headers, as: :json
      user.update_column(:deletion_scheduled_at, 31.days.ago) # simulate grace elapsed

      FinalizeAccountDeletionsJob.perform_now

      user.reload
      expect(user.deleted_at).to be_present
      expect(user.full_name).to eq("Deleted user")
      expect(user.active_for_authentication?).to be(false)
      expect(Message.exists?(msg.id)).to be(true) # history retained for the buyer
    end

    it "does NOT finalize accounts still within the grace window" do
      delete "/api/v1/auth", headers: headers, as: :json # scheduled just now
      FinalizeAccountDeletionsJob.perform_now
      expect(user.reload.deleted_at).to be_nil
    end
  end

  it "frees the original email for a brand-new account once finalized" do
    original_email = user.email
    delete "/api/v1/auth", headers: headers, as: :json
    user.update_column(:deletion_scheduled_at, 31.days.ago)
    FinalizeAccountDeletionsJob.perform_now

    post "/api/v1/auth", params: {
      email: original_email,
      password: "Password123!",
      password_confirmation: "Password123!",
      firstname: "New",
      lastname: "Person"
    }, as: :json

    expect(response).to have_http_status(:ok)
    new_user = User.find_by(email: original_email)
    expect(new_user.id).not_to eq(user.id)
    expect(new_user.deleted_at).to be_nil
    expect(new_user.listings).to be_empty
  end
end
