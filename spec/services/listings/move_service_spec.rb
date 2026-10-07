require "rails_helper"

# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 5).
RSpec.describe Listings::MoveService do
  include ActiveJob::TestHelper

  let(:owner)   { create(:user) }
  let(:staff)   { create(:user) }
  let(:shop_a)  { create(:shop, owner: owner, name: "Safi Mobile") }
  let(:shop_b)  { create(:shop, owner: owner, name: "Safi Cosmetics") }
  let(:buyer)   { create(:user, preferred_language: "ps") }

  before do
    shop_a.shop_members.create!(user: staff, role: :staff)
  end

  def move(listing, actor, shop_id) = described_class.new(listing: listing, actor: actor, shop_id: shop_id).call

  def error_code(listing, actor, shop_id)
    move(listing, actor, shop_id)
    nil
  rescue described_class::Error => e
    e.code
  end

  describe "where it may go" do
    it "Me → a shop the poster is on; the poster stays the poster" do
      listing = create(:listing, :active, user: owner)
      move(listing, owner, shop_a.id)
      expect(listing.reload.shop).to eq(shop_a)
      expect(listing.user).to eq(owner)
    end

    it "shop → shop, by a member of both; the mover becomes the poster" do
      shop_b.shop_members.create!(user: staff, role: :staff)
      listing = create(:listing, :active, user: owner, shop: shop_a)
      move(listing, staff, shop_b.id)
      expect(listing.reload.shop).to eq(shop_b)
      expect(listing.user).to eq(staff)
    end

    it "shop → Me by the shop's owner, even for a product staff posted" do
      listing = create(:listing, :active, user: staff, shop: shop_a)
      move(listing, owner, "")
      expect(listing.reload.shop).to be_nil
      expect(listing.user).to eq(owner)
    end

    it "keeps the expiry and the feed position" do
      listing = create(:listing, :active, user: owner, expires_at: 40.days.from_now, created_at: 3.days.ago)
      expect { move(listing, owner, shop_a.id) }
        .not_to(change { listing.reload.slice(:expires_at, :bumped_at) })
    end

    it "refuses: a shop they're not on, a closed shop, the same place" do
      listing = create(:listing, :active, user: owner)
      stranger_shop = create(:shop)
      expect(error_code(listing, owner, stranger_shop.id)).to eq(:move_not_member)
      shop_b.update_columns(status: Shop.statuses[:suspended])
      expect(error_code(listing, owner, shop_b.id)).to eq(:shop_unavailable)
      expect(error_code(listing, owner, nil)).to eq(:move_same_place)
    end

    it "refuses: staff taking a product someone else posted home to Me" do
      listing = create(:listing, :active, user: owner, shop: shop_a)
      expect(error_code(listing, staff, nil)).to eq(:move_forbidden)
      expect(listing.reload.shop).to eq(shop_a)
    end

    it "refuses: a held, sold or removed listing" do
      held = create(:listing, :reserved, user: owner)
      expect(error_code(held, owner, shop_a.id)).to eq(:move_has_hold)
      sold = create(:listing, :sold, user: owner)
      expect(error_code(sold, owner, shop_a.id)).to eq(:move_not_movable)
      removed = create(:listing, :active, user: owner, removed_at: Time.current)
      expect(error_code(removed, owner, shop_a.id)).to eq(:move_not_movable)
    end
  end

  describe "the chats" do
    let(:listing) { create(:listing, :active, user: owner) }
    let!(:chat)   { create(:conversation, listing: listing, buyer: buyer) }

    it "stay with the old identity: told in the buyer's language, then closed" do
      expect { move(listing, owner, shop_a.id) }.to have_enqueued_job(BroadcastMessageJob)

      chat.reload
      expect(chat).to be_closed
      expect(chat.shop_id).to be_nil # still the person's chat
      notice = chat.messages.last
      expect(notice).to be_system
      expect(notice.body).to eq(I18n.t("listing_move.notice", locale: :ps, name: "Safi Mobile"))
      expect(notice.context).to include("notice" => "listing_moved", "shop_id" => shop_a.id, "name" => "Safi Mobile")
      expect(SendMessagePushJob).not_to have_been_enqueued
    end

    it "the buyer then starts a NEW chat with the shop; moving back reopens the old one" do
      move(listing, owner, shop_a.id)
      new_chat = Conversations::StartService.new(buyer: buyer, listing: listing.reload, message_body: "Salaam").call
      expect(new_chat).not_to eq(chat)
      expect(new_chat.shop_id).to eq(shop_a.id)

      move(listing.reload, owner, nil)
      back = Conversations::StartService.new(buyer: buyer, listing: listing.reload, message_body: "Again").call
      expect(back).to eq(chat)
      expect(back.reload).to be_open
    end
  end
end
