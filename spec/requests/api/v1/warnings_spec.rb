require "rails_helper"

# The signed-in user's view of their own warnings (for the mobile banner).
RSpec.describe "Warnings API", type: :request do
  let(:user)    { create(:user) }
  let(:admin)   { create(:admin_user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/users/warnings" do
    it "returns the user's warnings with active count + threshold" do
      user.issue_warning!(admin_user: admin, reason: "Spam listings", category: :spam)

      get "/api/v1/users/warnings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["warnings"].length).to eq(1)
      expect(body["warnings"].first).to include("reason" => "Spam listings", "active" => true)
      expect(body["meta"]).to include("active_count" => 1, "threshold" => 3)
    end

    it "requires authentication" do
      get "/api/v1/users/warnings", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/users/warnings/mark_seen" do
    it "acknowledges the user's active warnings" do
      warning = user.issue_warning!(admin_user: admin, reason: "x")

      put "/api/v1/users/warnings/mark_seen", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(warning.reload.acknowledged_at).to be_present
    end
  end

  describe "GET /api/v1/users/me" do
    it "includes the active warning count and threshold" do
      user.issue_warning!(admin_user: admin, reason: "x")

      get "/api/v1/users/me", headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["user"]["active_warnings_count"]).to eq(1)
      expect(body["user"]["warning_threshold"]).to eq(3)
    end
  end
end

# d0 hunt 2026-10-09: a warning from a report was stored as English text
# ("Reported as spam") and the apps show the reason verbatim, so a Pashto,
# Dari or Urdu user read it in English. It is stored as a code now and
# rendered in the reader's language; old English rows are recognised too.
RSpec.describe "Warnings from a report are in the reader's language", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, password: "changeme123!") }
  let(:user) { create(:user, preferred_language: "ps") }
  def reasons
    get "/api/v1/users/warnings", headers: auth_headers_for(user)
    JSON.parse(response.body)["warnings"].pluck("reason")
  end

  it "a warning issued from a report reads in Pashto for a Pashto user" do
    sign_in admin, scope: :admin_user
    report = create(:report, :against_user, reportable: user, reason: :fraud)
    patch warn_target_admin_report_path(report)
    expect(reasons).to eq([ I18n.t("accounts.report_warning.fraud", locale: :ps) ])
    expect(reasons.first).not_to include("Reported as")
  end

  it "an old English row ('Reported as wrong category') is translated too" do
    user.warnings.create!(reason: "Reported as wrong category", category: :other)
    expect(reasons).to eq([ I18n.t("accounts.report_warning.wrong_category", locale: :ps) ])
  end

  it "a reason an admin typed is shown as typed" do
    user.warnings.create!(reason: "Selling counterfeit phones", category: :fraud)
    expect(reasons).to eq([ "Selling counterfeit phones" ])
  end
end
