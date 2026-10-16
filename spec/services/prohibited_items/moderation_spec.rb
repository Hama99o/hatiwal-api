require "rails_helper"

RSpec.describe ProhibitedItems::Moderation do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:seller) { create(:user, preferred_language: "fa") }
  let(:listing) { create(:listing, :active, user: seller, title: "Pistol") }
  let!(:flag) { create(:flag, flaggable: listing, category: :firearms) }

  describe "#dismiss!" do
    it "closes the flag, dismisses its reports and tells nobody" do
      report = create(:report, :prohibited_item, reportable: listing)
      expect { described_class.new(flag, admin: admin, note: "toy").dismiss! }.not_to have_enqueued_job(SupportNoticeJob)
      expect(flag.reload).to have_attributes(status: "dismissed", action_taken: "dismiss", acted_by: admin, note: "toy")
      expect(report.reload).to be_dismissed
      expect(listing.reload).to be_active
    end
  end

  describe "#take_down!" do
    it "moves the listing to draft, resolves reports and queues the seller's message" do
      report = create(:report, :prohibited_item, reportable: listing)

      expect { described_class.new(flag, admin: admin, note: "no guns").take_down! }
        .to have_enqueued_job(SupportNoticeJob)
        .with(seller.id, "listing_prohibited_removed", nil, { "listing_id" => listing.id, "category" => "firearms", "note" => "no guns" })

      expect(listing.reload).to be_draft
      expect(report.reload).to be_resolved
      expect(flag.reload).to have_attributes(status: "actioned", action_taken: "take_down", category: "firearms", acted_by: admin)
      expect(seller.reload.active_warnings_count).to eq(0)
    end

    it "uses the admin's category over the flag's" do
      described_class.new(flag, admin: admin, category: "drugs").take_down!
      expect(flag.reload.category).to eq("drugs")
    end

    it "files a report-only flag under other when no category is given" do
      report_flag = create(:flag, :from_report, flaggable: create(:listing, :active, user: seller))
      described_class.new(report_flag, admin: admin).take_down!
      expect(report_flag.reload.category).to eq("other")
    end

    it "soft-removes a sold listing instead" do
      listing.update_columns(status: Listing.statuses[:sold])
      described_class.new(flag, admin: admin).take_down!
      expect(listing.reload).to be_sold.and(be_removed)
    end

    it "refuses a second decision" do
      described_class.new(flag, admin: admin).take_down!
      expect { described_class.new(flag, admin: admin).take_down!(warn: true) }
        .to raise_error(described_class::Refused)
      expect(seller.reload.active_warnings_count).to eq(0)
    end

    context "with a warning" do
      it "issues ONE strike through the existing warning system and says so" do
        expect { described_class.new(flag, admin: admin).take_down!(warn: true) }
          .to have_enqueued_job(SupportNoticeJob).with(seller.id, "listing_prohibited_removed", nil, hash_including("warnings" => 1))
        warning = seller.warnings.sole
        expect(warning).to have_attributes(category: "prohibited_item", admin_user: admin)
        expect(flag.reload.action_taken).to eq("take_down_warn")
      end

      it "suspends the seller at the third active warning (existing User#issue_warning! rule)" do
        2.times { seller.issue_warning!(reason: "earlier", category: :prohibited_item) }
        described_class.new(flag, admin: admin).take_down!(warn: true)
        expect(seller.reload).to be_suspended
      end
    end

    context "on a shop" do
      let(:shop) { create(:shop, owner: seller) }
      let(:shop_flag) { create(:flag, :on_shop, flaggable: shop, category: :alcohol) }

      it "suspends the shop through Shop#suspend! with the reason in the owner's language" do
        expect { described_class.new(shop_flag, admin: admin, note: "rename it").take_down! }
          .to have_enqueued_job(SupportNoticeJob).with(seller.id, "shop_suspended", shop.id, hash_including("reason"))
        expect(shop.reload).to be_suspended
        reason = enqueued_jobs.find { |j| j["job_class"] == "SupportNoticeJob" }["arguments"].last["reason"]
        expect(reason).to include(I18n.t("support.prohibited.reasons.alcohol", locale: :fa), "hatiwal.com/fa/prohibited-items", "rename it")
      end

      it "strikes the SHOP, not the owner's personal account (owner, 2026-10-16)" do
        described_class.new(shop_flag, admin: admin).take_down!(warn: true)
        expect(shop.warnings.count).to eq(1)
        expect(seller.warnings.count).to eq(0)
      end

      it "refuses a closed shop" do
        shop.update_columns(status: Shop.statuses[:closed])
        expect { described_class.new(shop_flag, admin: admin).take_down! }.to raise_error(described_class::Refused)
        expect(shop_flag.reload).to be_open
      end
    end

    context "a listing that belongs to a shop (owner, 2026-10-16: both answer)" do
      let(:poster) { create(:user, preferred_language: "ps") }
      let(:shop_owner) { create(:user) }
      let(:shop) { create(:shop, owner: shop_owner) }
      let(:shop_listing) do
        shop.shop_members.create!(user: poster, role: :staff)
        create(:listing, :active, user: poster, shop: shop, title: "AK")
      end
      let!(:shop_listing_flag) { create(:flag, flaggable: shop_listing, category: :firearms) }

      it "strikes BOTH the poster and the shop, drafts the listing, and records the poster on the shop warning" do
        described_class.new(shop_listing_flag, admin: admin).take_down!(warn: true)
        expect(poster.active_warnings_count).to eq(1)
        expect(shop.active_warnings_count).to eq(1)
        expect(shop_listing.reload).to be_draft
        expect(shop.warnings.last).to have_attributes(posted_by_id: poster.id, listing_id: shop_listing.id)
      end

      it "messages the poster's account and the shop owner (naming the poster)" do
        described_class.new(shop_listing_flag, admin: admin).take_down!(warn: true)
        expect(SupportNoticeJob).to have_been_enqueued
          .with(poster.id, "listing_prohibited_removed", shop.id, hash_including("warnings" => 1))
        expect(SupportNoticeJob).to have_been_enqueued
          .with(shop_owner.id, "listing_prohibited_shop_owner", shop.id, hash_including("warnings" => 1, "poster" => poster.full_name))
      end

      it "a plain take_down (no warning) strikes neither" do
        described_class.new(shop_listing_flag, admin: admin).take_down!
        expect([ poster.active_warnings_count, shop.active_warnings_count ]).to eq([ 0, 0 ])
      end

      it "is idempotent — a second decision raises, never a second strike each" do
        described_class.new(shop_listing_flag, admin: admin).take_down!(warn: true)
        expect { described_class.new(shop_listing_flag, admin: admin).take_down!(warn: true) }
          .to raise_error(described_class::Refused)
        expect([ poster.active_warnings_count, shop.active_warnings_count ]).to eq([ 1, 1 ])
      end

      it "a NON-shop listing strikes only the poster (unchanged)" do
        personal = create(:listing, :active, user: poster, title: "Lone")
        personal_flag = create(:flag, flaggable: personal, category: :firearms)
        described_class.new(personal_flag, admin: admin).take_down!(warn: true)
        expect(poster.active_warnings_count).to eq(1)
      end
    end
  end
end
