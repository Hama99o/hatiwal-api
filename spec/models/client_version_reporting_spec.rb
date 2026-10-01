require "rails_helper"

RSpec.describe ClientVersionReporting do
  let(:user) { create(:user) }
  let(:now)  { Time.zone.parse("2026-10-01 12:00") }
  let(:okhttp) { "okhttp/4.12.0" }

  it "records a reported version and platform" do
    user.record_client!(version: "1.1.0", platform: "android", user_agent: okhttp, now: now)

    expect(user.reload).to have_attributes(last_app_version: "1.1.0", last_app_platform: "android",
                                           last_app_version_at: now, legacy_client_seen_at: nil)
  end

  it "counts a headerless NATIVE request as a legacy (v1.0.4 or older) client" do
    user.record_client!(version: nil, platform: nil, user_agent: "Hatiwal/12 CFNetwork/1498 Darwin/23.6.0", now: now)

    expect(user.reload.legacy_client_seen_at).to eq(now)
    expect(User.on_legacy_client_since(now - 1.day)).to include(user)
  end

  # hatiwal-web calls the API from Node without these headers.
  it "does not count a headerless web (Node) request as an old phone" do
    user.record_client!(version: nil, platform: nil, user_agent: "node", now: now)
    user.record_client!(version: nil, platform: nil, user_agent: nil, now: now)

    expect(user.reload.legacy_client_seen_at).to be_nil
  end

  it "ignores a malformed version and an unknown platform" do
    user.record_client!(version: "<script>", platform: "android", user_agent: okhttp, now: now)
    expect(user.reload.last_app_version).to be_nil

    user.record_client!(version: "1.1.0", platform: "toaster", user_agent: okhttp, now: now)
    expect(user.reload).to have_attributes(last_app_version: "1.1.0", last_app_platform: nil)
  end

  it "writes at most once an hour when nothing changed, but at once on an upgrade" do
    user.record_client!(version: "1.1.0", platform: "ios", user_agent: okhttp, now: now)
    user.record_client!(version: "1.1.0", platform: "ios", user_agent: okhttp, now: now + 10.minutes)
    expect(user.reload.last_app_version_at).to eq(now)

    user.record_client!(version: "1.2.0", platform: "ios", user_agent: okhttp, now: now + 11.minutes)
    expect(user.reload).to have_attributes(last_app_version: "1.2.0", last_app_version_at: now + 11.minutes)

    user.record_client!(version: "1.2.0", platform: "ios", user_agent: okhttp, now: now + 2.hours)
    expect(user.reload.last_app_version_at).to eq(now + 2.hours)
  end

  describe ".push_reach_since" do
    it "lists every platform with users and token holders, zeros included" do
      create(:user, last_app_platform: "ios", last_app_version: "1.1.0", last_app_version_at: now, push_token: "ExponentPushToken[a]")
      create(:user, last_app_platform: "ios", last_app_version: "1.1.0", last_app_version_at: now)
      create(:user, last_app_platform: "android", last_app_version: "1.1.0", last_app_version_at: now)

      reach = User.push_reach_since(now - 1.day)

      expect(reach).to eq("ios" => { users: 2, with_token: 1, reasons: {} }, "android" => { users: 1, with_token: 0, reasons: {} })
    end

    it "still lists a platform nobody reported, as zero of zero" do
      expect(User.push_reach_since(now - 1.day)["android"]).to eq(users: 0, with_token: 0, reasons: {})
    end
  end

  describe "#push_registration_error=" do
    it "stores one capped, single-line reason with a timestamp" do
      user.update!(push_registration_error: "token:\n Default FirebaseApp\tis not initialized" + ("x" * 1000))

      expect(user.push_registration_error).to start_with("token: Default FirebaseApp is not initialized")
      expect(user.push_registration_error.length).to eq(ClientVersionReporting::PUSH_ERROR_MAX)
      expect(user.push_registration_error).not_to match(/[[:cntrl:]]/)
      expect(user.push_registration_error_at).to be_present
    end

    it "is cleared by a blank report, and by a token finally registering" do
      user.update!(push_registration_error: "token: boom")
      user.update!(push_token: "ExponentPushToken[ok]")
      expect(user.reload).to have_attributes(push_registration_error: nil, push_registration_error_at: nil)

      user.update!(push_registration_error: "permission: denied")
      user.update!(push_registration_error: "")
      expect(user.reload.push_registration_error).to be_nil
    end
  end

  it "reports the most common reasons for platforms without tokens" do
    2.times do
      create(:user, last_app_platform: "android", last_app_version: "1.1.0", last_app_version_at: now,
                    push_registration_error: "token: Default FirebaseApp is not initialized")
    end
    create(:user, last_app_platform: "android", last_app_version: "1.1.0", last_app_version_at: now,
                  push_registration_error: "permission: denied")

    reasons = User.push_reach_since(now - 1.day)["android"][:reasons]

    expect(reasons.first).to eq([ "token: Default FirebaseApp is not initialized", 2 ])
    expect(reasons.size).to eq(2)
  end
end
