require "rails_helper"

# Edge-case pass, 2026-10-08 — the shop team (SHOP-3).
RSpec.describe "Shop team — edge cases", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:shop) { create(:shop) }
  let(:owner) { shop.owner }
  let(:manager) { create(:user, :confirmed) }
  let(:staff) { create(:user, :confirmed) }

  before do
    shop.shop_members.create!(user: manager, role: :manager)
    shop.shop_members.create!(user: staff, role: :staff)
  end

  def refused(code)
    raise_error(ShopInvite::Refused) { |e| expect(e.code).to eq(code) }
  end

  describe "inviting someone already on the team" do
    it "an email invite is refused at once" do
      expect { shop.invite!(by: owner, email: staff.email.upcase) }.to refused(:already_member)
    end

    it "a link invite opened by a member is refused, and nothing changes" do
      invite = shop.invite!(by: owner)
      expect { invite.accept!(staff) }.to refused(:already_member)
      expect(shop.shop_members.find_by(user: staff)).to be_staff
      expect(invite.reload).to be_pending
    end
  end

  describe "accepting an invite that can no longer be used" do
    let(:newcomer) { create(:user, :confirmed) }

    it "expired" do
      invite = shop.invite!(by: owner)
      travel_to(invite.expires_at + 1.second) do
        expect { invite.accept!(newcomer) }.to refused(:invite_expired)
      end
      expect(shop.member?(newcomer)).to be(false)
    end

    it "cancelled by the owner" do
      invite = shop.invite!(by: owner)
      invite.cancel!(owner)
      expect { invite.accept!(newcomer) }.to refused(:invite_cancelled)
    end

    it "already used by someone else" do
      invite = shop.invite!(by: owner)
      invite.accept!(newcomer)
      expect { invite.accept!(create(:user, :confirmed)) }.to refused(:invite_used)
    end

    it "the shop was closed after the invite was sent" do
      invite = shop.invite!(by: owner)
      shop.close!
      expect { invite.accept!(newcomer) }.to raise_error(ShopInvite::Refused)
      expect(shop.member?(newcomer)).to be(false)
    end
  end

  it "the owner (the last owner) cannot leave; they transfer first" do
    expect { shop.leave!(owner) }.to refused(:owner_cannot_leave)
    expect { shop.remove_team_member!(owner, by: manager) }.to refused(:owner_cannot_leave)
  end

  # The controller authorizes, then calls the model. A role change landing in
  # between must not let the old role act: the model re-checks the actor.
  describe "a role change racing with an action" do
    it "a manager made Staff cannot then remove a Staff member" do
      shop.change_role!(manager, role: :staff, by: owner)
      expect { shop.remove_team_member!(staff, by: manager) }.to refused(:forbidden)
      expect(shop.member?(staff)).to be(true)
    end

    it "a manager removed from the team cannot then invite" do
      shop.remove_team_member!(manager, by: owner)
      expect { shop.invite!(by: manager) }.to refused(:forbidden)
    end

    it "an old owner (now a manager after a transfer) cannot then change roles" do
      shop.transfer_ownership!(manager, by: owner)
      expect { shop.change_role!(staff, role: :manager, by: owner) }.to refused(:forbidden)
      expect(shop.shop_members.find_by(user: staff)).to be_staff
    end
  end

  describe "a removed member's chats and listings" do
    let(:buyer) { create(:user, :confirmed) }
    let!(:product) { create(:listing, user: staff, shop: shop) }
    # The factory makes the poster the seller; Conversations::StartService makes
    # a shop product's seller the shop's OWNER, which is what this pins.
    let!(:chat) { create(:conversation, listing: product, buyer: buyer, shop: shop).tap { |c| c.update_columns(seller_id: owner.id) } }

    before { shop.remove_team_member!(staff, by: owner) }

    it "the shop keeps the product (the owner's now); the removed member can no longer manage it" do
      expect(product.reload.user_id).to eq(owner.id)
      expect(product.manageable_by?(staff)).to be(false)
    end

    it "the shop's chats leave their inbox and access" do
      expect(chat.reload.participant?(staff)).to be(false)
      expect(Conversation.for_user(staff.reload)).not_to include(chat)
      expect(chat.participant?(owner)).to be(true)
    end
  end
end
