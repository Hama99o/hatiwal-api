require "rails_helper"

# UPD-1 — status rules and the safety guards (docs/FORCE_UPDATE.md).
RSpec.describe AppReleaseSetting, type: :model do
  let(:settings) { { "min_version" => "1.1.6", "latest_version" => "1.1.7" } }

  describe ".status" do
    {
      "1.1.5" => "blocked", "1.1.6" => "soft", "1.1.6.1" => "soft", "1.1.7" => "ok", "1.2.0" => "ok", "1.10.0" => "ok"
    }.each do |version, expected|
      it("#{version} → #{expected}") { expect(described_class.status(version, settings)).to eq(expected) }
    end

    it "never blocks a missing or malformed version" do
      [ nil, "", "garbage", "1.2.3.4.5" ].each { |v| expect(described_class.status(v, settings)).to eq("ok") }
    end

    it "is ok when nothing is set" do
      expect(described_class.status("1.0.0", {})).to eq("ok")
    end
  end

  describe "validations" do
    it "refuses a minimum above the released version" do
      setting = build(:app_release_setting, android_released_version: "1.1.6", android_min_version: "1.1.7")
      expect(setting).not_to be_valid
      expect(setting.errors.full_messages.join).to include("No 1.1.7 is released for Android")
    end

    it "refuses a latest above the released version, and any version without a released one" do
      expect(build(:app_release_setting, ios_released_version: "1.1.6", ios_latest_version: "1.1.7")).not_to be_valid
      expect(build(:app_release_setting, ios_released_version: nil, ios_latest_version: "1.1.7")).not_to be_valid
    end

    it "refuses malformed versions and non-https store links" do
      expect(build(:app_release_setting, android_min_version: "one")).not_to be_valid
      expect(build(:app_release_setting, android_store_url: "http://example.com")).not_to be_valid
    end

    it "has its message in all four locales" do
      User::SUPPORTED_LANGUAGES.each do |locale|
        I18n.with_locale(locale) do
          setting = described_class.new
          setting.errors.add(:android_min_version, :not_released, version: "1.1.7", platform: "Android")
          expect(setting.errors.full_messages.join).not_to include("Translation missing"), locale
        end
      end
    end
  end

  it "knows which minimums a change raises" do
    setting = create(:app_release_setting, android_min_version: "1.1.6")
    setting.assign_attributes(android_min_version: "1.1.7", ios_min_version: "1.1.7")
    expect(setting.raised_minimums).to contain_exactly("android", "ios")
    setting.assign_attributes(android_min_version: "1.1.5", ios_min_version: nil)
    expect(setting.raised_minimums).to be_empty
  end

  it "fills the default store links and clears the cache on save" do
    store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(store)
    setting = create(:app_release_setting)
    expect(described_class.cached_values["android"]["store_url"]).to include("com.hatiwal.app")
    setting.update!(android_min_version: "1.1.7")
    expect(described_class.cached_values["android"]["min_version"]).to eq("1.1.7")
  end
end
