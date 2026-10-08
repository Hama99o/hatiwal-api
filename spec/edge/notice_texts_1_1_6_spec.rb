require "rails_helper"

# Edge-case pass, 2026-10-08 — every in-app Support notice and push that 1.1.6
# sends, in en / ps / fa / ur: present (no "translation missing"), the same
# %{placeholders} as English (a dropped %{shop} loses the identity), no English
# left in the RTL locales, and the notice's button opens the right thing for
# the right identity (the shop's id for a shop notice, "me" for a person's).
RSpec.describe "1.1.6 notice and push texts", type: :model do
  LOCALES = %i[en ps fa ur].freeze
  NOTICE_KEYS = (SupportNoticeJob::NOTICES.keys + SupportNoticeJob::TEAM_NOTICES.keys +
                 SupportNoticeJob::LISTING_NOTICES).uniq.freeze
  PUSH_KEYS = (%w[push.support.title push.listing_expiry.week_title push.listing_expiry.day_title push.listing_expiry.body] +
               %w[shop_invite shop_member_joined shop_membership_changed_removed shop_membership_changed_closed
                  shop_membership_changed_role_changed shop_owner_changed].map { |k| "push.shop_team.#{k}" }).freeze
  ROLE_KEYS = %w[owner manager staff].map { |r| "support.team_roles.#{r}" }.freeze
  # Latin words allowed in ps/fa/ur text: the brand and the store names, as written in the apps.
  LATIN_OK = %w[Hatiwal App Store Google Play].freeze

  def text(key, locale) = I18n.t(key, locale: locale, raise: true)
  def placeholders(str) = str.to_s.scan(/%\{(\w+)\}/).flatten.sort

  (NOTICE_KEYS.map { |k| "support.notices.#{k}" } + PUSH_KEYS + ROLE_KEYS).each do |key|
    describe key do
      it "exists in every locale with English's placeholders" do
        en = placeholders(text(key, :en))
        LOCALES.each do |locale|
          expect { text(key, locale) }.not_to raise_error, "#{key} missing in #{locale}"
          expect(placeholders(text(key, locale))).to eq(en), "#{key} in #{locale}: placeholders differ from en"
        end
      end

      it "has no English left in ps / fa / ur" do
        %i[ps fa ur].each do |locale|
          str = text(key, locale).gsub(/%\{\w+\}/, "")
          latin = str.scan(/[A-Za-z]{3,}/) - LATIN_OK
          expect(latin).to be_empty, "#{key} in #{locale} has Latin words: #{latin.inspect} — #{str}"
          expect(str).not_to eq(text(key, :en).gsub(/%\{\w+\}/, "")), "#{key} in #{locale} is the English text"
        end
      end
    end
  end

  describe "the button opens the right thing, for the right identity" do
    let(:job) { SupportNoticeJob.new }
    let(:shop) { create(:shop) }
    let(:invite) { create(:shop_invite, shop: shop) }
    let(:listing) { create(:listing, :active, user: shop.owner, shop: shop) }

    it "a shop's notices carry the SHOP (its id); a person's verification opens 'me'" do
      expect(job.send(:action_for, :shop_verified, shop: shop)["params"]).to eq("shop_id" => shop.id)
      expect(job.send(:action_for, :shop_verification_rejected, shop: shop)["params"]).to eq("subject" => "shop", "shop_id" => shop.id)
      expect(job.send(:action_for, :shop_badge_applicant_left, shop: shop)["params"]).to eq("subject" => "shop", "shop_id" => shop.id)
      expect(job.send(:action_for, :user_verification_rejected)["params"]).to eq("subject" => "me")
      expect(job.send(:action_for, :shop_invite_received, shop: shop, invite: invite)["params"]).to eq("token" => invite.token)
      expect(job.send(:action_for, :listing_expires_day, listing: listing)["params"]).to eq("listing_id" => listing.id, "shop_id" => shop.id)
      expect(job.send(:action_for, :shop_member_removed, shop: shop)).to be_nil # nothing left to open
    end

    it "every button's label exists for the apps (chat.noticeAction.*) — listed for the clients' check" do
      labels = SupportNoticeJob::ACTIONS.values.map(&:last).uniq.sort
      expect(labels).to all(match(/\A[a-zA-Z]+\z/))
    end

    it "shop notices go to the shop's thread; a person's to their own" do
      expect(SupportNoticeJob::SHOP_THREAD_NOTICES).to include(:shop_verified, :shop_member_joined, :shop_badge_applicant_left)
      expect(SupportNoticeJob::SHOP_THREAD_NOTICES).not_to include(:shop_invite_received, :shop_role_changed, :shop_member_removed,
                                                                    :user_verified, :listing_expires_week)
    end
  end
end
