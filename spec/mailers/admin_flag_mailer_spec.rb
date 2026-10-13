require "rails_helper"
require Rails.root.join("spec/mailers/previews/admin_flag_mailer_preview").to_s

RSpec.describe AdminFlagMailer, type: :mailer do
  let(:admin) { create(:admin_user, email: "owner@hatiwal.com") }
  let(:listing) { create(:listing, :active, title: "Hunting rifle") }
  let(:flag) { create(:flag, flaggable: listing, category: :firearms, matched_term: "rifle") }

  it "tells one admin what was flagged and links the flag" do
    mail = described_class.new_flag(flag, admin)

    expect(mail.to).to eq([ "owner@hatiwal.com" ])
    expect(mail.subject).to eq("[Hatiwal] Flagged listing: Hunting rifle (Firearms)")
    [ mail.html_part, mail.text_part ].each do |part|
      expect(part.body.encoded).to include("Hunting rifle", "rifle", "Firearms", "http://example.com/admin/flags/#{flag.id}")
    end
  end

  it "names a shop and a report-only flag" do
    shop_flag = create(:flag, :on_shop, :from_report)
    mail = described_class.new_flag(shop_flag, admin)
    expect(mail.subject).to include("Flagged shop", "prohibited item report")
    expect(mail.text_part.body.encoded).to include("(reported)")
  end

  it "has a working preview" do
    flag
    expect(AdminFlagMailerPreview.new.new_flag.subject).to include("Flagged listing")
  end
end
