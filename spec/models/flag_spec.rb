require "rails_helper"

RSpec.describe Flag, type: :model do
  include ActiveJob::TestHelper

  let!(:pistol) { create(:prohibited_term, term: "pistol", category: :firearms) }
  let!(:tramadol) { create(:prohibited_term, term: "tramadol", category: :medicine) }

  describe "associations and enums" do
    it { is_expected.to belong_to(:flaggable) }
    it { is_expected.to belong_to(:acted_by).class_name(AdminUser.name).optional }
    it { is_expected.to define_enum_for(:status).with_values(open: 0, dismissed: 1, actioned: 2) }
    it { is_expected.to define_enum_for(:source).with_values(term: 0, report: 1).with_prefix(:source) }
  end

  describe "scanning a listing" do
    it "opens a flag when a live listing is created with a term, and changes nothing" do
      listing = create(:listing, :active, title: "Old pistol")
      flag = listing.flags.sole
      expect(flag).to have_attributes(status: "open", source: "term", category: "firearms", matched_term: "pistol", prohibited_term: pistol)
      expect(listing.reload).to be_active
    end

    it "does not scan a draft, then scans it when it is published" do
      listing = create(:listing, :with_image, title: "Old pistol")
      expect(listing.flags).to be_empty
      listing.update!(status: :active)
      expect(listing.flags.count).to eq(1)
    end

    it "scans an edit of a live listing's text" do
      listing = create(:listing, :active, title: "Old phone")
      listing.update!(description: "comes with a pistol")
      expect(listing.flags.sole.matched_term).to eq("pistol")
    end

    it "keeps ONE open flag per listing, however many edits match" do
      listing = create(:listing, :active, title: "pistol")
      listing.update!(description: "pistol and tramadol")
      expect(listing.flags.count).to eq(1)
    end

    it "files the flag under the forbidden category before medicine" do
      listing = create(:listing, :active, title: "tramadol and a pistol")
      expect(listing.flags.sole).to have_attributes(category: "firearms", matched_term: "pistol, tramadol")
    end

    it "does not bring back a flag an admin dismissed for the same words" do
      listing = create(:listing, :active, title: "pistol")
      listing.flags.sole.update!(status: :dismissed)
      listing.update!(description: "still a pistol")
      expect(listing.flags.open).to be_empty
    end

    it "flags again after a take-down when the listing is published again" do
      listing = create(:listing, :active, :with_image, title: "pistol")
      listing.flags.sole.update!(status: :actioned)
      listing.update!(status: :draft)
      listing.update!(status: :active)
      expect(listing.flags.open.count).to eq(1)
    end

    it "never fails the save when scanning breaks" do
      allow(ProhibitedItems::Matcher).to receive(:current).and_raise(StandardError, "boom")
      expect { create(:listing, :active, title: "pistol") }.not_to raise_error
    end
  end

  describe "scanning a shop" do
    it "opens a flag on the shop's name or description" do
      shop = create(:shop, description: "Pistol repair and sale")
      expect(shop.flags.sole).to have_attributes(category: "firearms", flaggable: shop)
    end

    it "ignores a save that does not touch the text" do
      shop = create(:shop, description: "Phones")
      shop.update!(phone: "+93 70 000 0000")
      expect(shop.flags).to be_empty
    end
  end

  describe "prohibited-item reports" do
    let(:listing) { create(:listing, :active, title: "Nice phone", user: create(:user, preferred_language: "en")) }

    it "opens a report flag on the first report and joins it after" do
      create(:report, :prohibited_item, reportable: listing)
      flag = listing.flags.sole
      expect(flag).to have_attributes(source: "report", category: nil)

      create(:report, :prohibited_item, reportable: listing)
      expect(listing.flags.count).to eq(1)
      expect(flag.distinct_reporters).to eq(2)
    end

    it "joins an open term flag" do
      listing.update!(title: "pistol")
      create(:report, :prohibited_item, reportable: listing)
      expect(listing.flags.sole.source).to eq("term")
    end

    it "ignores reports for other reasons" do
      create(:report, reason: :spam, reportable: listing)
      expect(listing.flags).to be_empty
    end

    describe "3 distinct reporters move the listing to draft" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
      end

      it "drafts the listing on the third, tells the seller, logs it, and leaves the flag open" do
        2.times { create(:report, :prohibited_item, reportable: listing) }
        expect(listing.reload).to be_active

        perform_enqueued_jobs(only: SupportNoticeJob) { create(:report, :prohibited_item, reportable: listing) }

        expect(listing.reload).to be_draft
        expect(listing.flags.sole).to be_open
        expect(AdminAuditLog.where(action: "auto_draft_listing", target: listing)).to exist
        thread = Conversation.kind_support.find_by(buyer_id: listing.user_id)
        expect(thread.messages.sole.body).to include(listing.title, "hatiwal.com/en/prohibited-items")
      end

      it "does nothing more on a fourth report" do
        3.times { create(:report, :prohibited_item, reportable: listing) }
        expect { create(:report, :prohibited_item, reportable: listing) }.not_to have_enqueued_job(SupportNoticeJob)
        expect(AdminAuditLog.where(action: "auto_draft_listing").count).to eq(1)
      end
    end
  end

  describe "emails to admins on a NEW flag" do
    let!(:admins) { create_list(:admin_user, 2) }

    around do |example|
      Rails.application.config.x.flag_emails_enabled = true
      example.run
    ensure
      Rails.application.config.x.flag_emails_enabled = false
    end

    it "emails every unlocked admin once per new flag" do
      create(:admin_user, locked_at: Time.current)
      listing = nil
      expect { listing = create(:listing, :active, title: "pistol") }
        .to have_enqueued_mail(AdminFlagMailer, :new_flag).exactly(2).times
      expect { listing.update!(description: "pistol again") }.not_to have_enqueued_mail(AdminFlagMailer, :new_flag)
    end

    it "sends nothing when FLAG_EMAILS_ENABLED is off" do
      Rails.application.config.x.flag_emails_enabled = false
      expect { create(:listing, :active, title: "pistol") }.not_to have_enqueued_mail(AdminFlagMailer, :new_flag)
    end
  end

  describe "#responsible_user" do
    it "is the listing's seller, or the shop's owner" do
      listing = create(:listing, :active)
      shop = create(:shop)
      expect(build(:flag, flaggable: listing).responsible_user).to eq(listing.user)
      expect(build(:flag, flaggable: shop).responsible_user).to eq(shop.owner)
    end
  end
end
