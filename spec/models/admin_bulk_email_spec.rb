require "rails_helper"

RSpec.describe AdminBulkEmail do
  let(:content) { { "en" => { "subject" => "Hi", "body" => "Hello" }, "ps" => { "subject" => "سلام", "body" => "ښه" } } }

  it "keeps only languages with both subject and body" do
    raw = content.merge("fa" => { "subject" => "only a subject", "body" => "" })
    expect(described_class.normalize_content(raw).keys).to eq(%w[en ps])
  end

  it "gives each user their language, else the chosen fallback" do
    bulk = described_class.new(content: content, fallback_locale: "ps")
    expect(bulk.locale_for("en")).to eq("en")
    expect(bulk.locale_for("ur")).to eq("ps")
    expect(bulk.locale_for(nil)).to eq("ps")
  end

  it "requires the fallback language to be written" do
    bulk = described_class.new(admin_user: create(:admin_user), content: content.slice("ps"), fallback_locale: "en")
    expect(bulk).not_to be_valid
    expect(bulk.errors.full_messages.join).to include("Write the English version")
  end
end
