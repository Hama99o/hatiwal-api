require "rails_helper"

# UPD-1 — "Message users on old versions": only old builds, once per target.
RSpec.describe AppUpdateNotice, type: :model do
  include ActiveJob::TestHelper

  before { allow(Conversation).to receive(:admin_initiate_enabled?).and_return(true) }

  it "messages only users below the target, on that platform, once" do
    old = create(:user, last_app_platform: "android", last_app_version: "1.1.5")
    older = create(:user, last_app_platform: "android", last_app_version: "1.0.9")
    current = create(:user, last_app_platform: "android", last_app_version: "1.1.7")
    ios_old = create(:user, last_app_platform: "ios", last_app_version: "1.1.5")

    expect { expect(described_class.notify_old_versions!(platform: "android", target: "1.1.7")).to eq(2) }
      .to have_enqueued_job(SupportNoticeJob).exactly(2).times
    expect(described_class.pluck(:user_id)).to contain_exactly(old.id, older.id)
    expect(described_class.where(user: [ current, ios_old ])).to be_empty

    expect { expect(described_class.notify_old_versions!(platform: "android", target: "1.1.7")).to eq(0) }
      .not_to have_enqueued_job(SupportNoticeJob)
  end

  it "refuses an unknown platform or a non-version" do
    expect { described_class.notify_old_versions!(platform: "web", target: "1.1.7") }.to raise_error(ArgumentError)
    expect { described_class.notify_old_versions!(platform: "ios", target: "latest") }.to raise_error(ArgumentError)
  end

  it "has the update message in all four locales" do
    User::SUPPORTED_LANGUAGES.each do |locale|
      expect(I18n.t("support.notices.app_update_available", locale: locale, raise: true)).to include("📲")
    end
  end
end
