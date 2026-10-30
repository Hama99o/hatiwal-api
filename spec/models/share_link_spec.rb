require "rails_helper"

# IDEA-8 (1.2.1, hatiwal-mobile docs/design/SHARE_AND_QR.md §3.1): one link for every share.
# `/l/<id>` and `/s/<id>` stay on the app-link paths; `lang` (the sharer's language) and `src`
# (what shared it) are WHITELISTED — nothing built from user input ever reaches the link.
RSpec.describe ShareLink do
  let(:listing) { create(:listing, :active) }
  let(:shop) { create(:shop) }

  around do |example|
    previous = ENV.fetch("PUBLIC_SHARE_BASE_URL", nil)
    ENV["PUBLIC_SHARE_BASE_URL"] = "https://hatiwal.com"
    example.run
  ensure
    ENV["PUBLIC_SHARE_BASE_URL"] = previous
  end

  it "builds the short app-link URL with the sharer's language and the source" do
    expect(described_class.for(listing, lang: "ps", src: "wa")).to eq("https://hatiwal.com/l/#{listing.id}?lang=ps&src=wa")
    expect(described_class.for(shop, lang: "fa", src: "qr")).to eq("https://hatiwal.com/s/#{shop.id}?lang=fa&src=qr")
    expect(described_class.for(shop)).to eq("https://hatiwal.com/s/#{shop.id}")
  end

  it "drops a language or a source that is not on the list (ur is hidden; anything else is ignored)" do
    expect(described_class.for(listing, lang: "ur", src: "wa")).to eq("https://hatiwal.com/l/#{listing.id}?src=wa")
    expect(described_class.for(listing, lang: "//evil.example", src: "javascript:alert(1)"))
      .to eq("https://hatiwal.com/l/#{listing.id}")
  end

  it "is nil without PUBLIC_SHARE_BASE_URL (no host is ever hardcoded)" do
    ENV["PUBLIC_SHARE_BASE_URL"] = nil

    expect(described_class.for(listing, lang: "ps", src: "qr")).to be_nil
  end

  describe ".log_visit" do
    it "logs one line for a known source, with the whitelisted language" do
      allow(Rails.logger).to receive(:info).and_call_original

      described_class.log_visit(:listing, 86, src: "wa", lang: "ps")

      expect(Rails.logger).to have_received(:info).with("[share_visit] src=wa kind=listing id=86 lang=ps")
    end

    it "logs nothing without a known source, and never echoes an unknown value" do
      allow(Rails.logger).to receive(:info).and_call_original

      described_class.log_visit(:listing, 86, src: "evil\nline", lang: "ps")
      described_class.log_visit(:shop, 4, src: "qr", lang: "<script>")

      expect(Rails.logger).to have_received(:info).with("[share_visit] src=qr kind=shop id=4 lang=").once
      expect(Rails.logger).not_to have_received(:info).with(/evil|script/)
    end
  end
end
