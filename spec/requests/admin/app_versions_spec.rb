require "rails_helper"

# UPD-1 — admin "App versions" (docs/FORCE_UPDATE.md).
RSpec.describe "Admin app versions", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let!(:setting) { create(:app_release_setting) }

  before do
    sign_in admin, scope: :admin_user
    create_list(:user, 2, last_app_platform: "android", last_app_version: "1.1.6")
    create(:user, last_app_platform: "android", last_app_version: "1.1.7")
    create(:user, last_app_platform: "ios", last_app_version: "1.1.5")
  end

  it "shows the settings, who is on what, and the impact" do
    get admin_app_versions_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("app-versions-android", "1.1.6 — 2", "Reminded: 2 users")
  end

  it "refuses a minimum above the released version" do
    patch admin_app_versions_path, params: { app_release_setting: { android_min_version: "1.1.8" }, confirm_raise: "1" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("No 1.1.8 is released for Android")
    expect(setting.reload.android_min_version).to eq("1.1.6")
  end

  it "asks for confirmation before RAISING a minimum, then saves and logs it" do
    patch admin_app_versions_path, params: { app_release_setting: { android_min_version: "1.1.7" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("app-versions-confirm", "2</strong> Android users will be blocked")
    expect(setting.reload.android_min_version).to eq("1.1.6")

    patch admin_app_versions_path, params: { app_release_setting: { android_min_version: "1.1.7" }, confirm_raise: "1", note: "API break" }
    expect(response).to redirect_to(admin_app_versions_path)
    expect(setting.reload.android_min_version).to eq("1.1.7")
    log = AdminAuditLog.find_by(action: "app_versions_update")
    expect(log.details).to include("android_min_version: 1.1.6 → 1.1.7", "API break")
  end

  it "lowers a minimum without asking" do
    patch admin_app_versions_path, params: { app_release_setting: { android_min_version: "" } }
    expect(response).to redirect_to(admin_app_versions_path)
    expect(setting.reload.android_min_version).to be_nil
  end

  it "clears the cached config on save" do
    store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(store)
    AppReleaseSetting.cached_values
    patch admin_app_versions_path, params: { app_release_setting: { android_latest_version: "1.1.6" } }
    expect(AppReleaseSetting.cached_values["android"]["latest_version"]).to eq("1.1.6")
  end

  it "messages users on old versions once, and logs it" do
    allow(Conversation).to receive(:admin_initiate_enabled?).and_return(true)
    expect do
      post message_old_versions_admin_app_versions_path, params: { platform: "android", target_version: "1.1.7" }
    end.to have_enqueued_job(SupportNoticeJob).exactly(2).times
    expect(flash[:notice]).to include("2 users")
    expect(AdminAuditLog.find_by(action: "app_update_message").details).to include("android below 1.1.7: 2 queued")

    expect do
      post message_old_versions_admin_app_versions_path, params: { platform: "android", target_version: "1.1.7" }
    end.not_to have_enqueued_job(SupportNoticeJob)
  end

  it "asks a SECOND time when a new minimum blocks 90% or more of reported users (typo guard)" do
    params = { app_release_setting: { android_released_version: "1.1.70", android_min_version: "1.1.70" }, confirm_raise: "1" }
    patch admin_app_versions_path, params: params
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("app-versions-mass-block", "100%")
    expect(setting.reload.android_min_version).to eq("1.1.6")

    patch admin_app_versions_path, params: params.merge(confirm_mass_block: "1")
    expect(setting.reload.android_min_version).to eq("1.1.70")
  end

  it "refuses to message users towards a version that is not released, and logs the target" do
    allow(Conversation).to receive(:admin_initiate_enabled?).and_return(true)
    expect do
      post message_old_versions_admin_app_versions_path, params: { platform: "android", target_version: "1.1.9" }
    end.not_to have_enqueued_job(SupportNoticeJob)
    expect(flash[:alert]).to include("not released for Android")

    post message_old_versions_admin_app_versions_path, params: { platform: "android", target_version: "1.1.7" }
    expect(AdminAuditLog.find_by(action: "app_update_message").target).to eq(setting)
  end
end
