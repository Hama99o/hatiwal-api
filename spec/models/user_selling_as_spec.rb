require "rails_helper"

# SHOP-1 — "Selling as" (users.active_shop_id), checked on every read.
RSpec.describe User, "selling as" do
  let(:user) { create(:user) }
  let(:shop) { create(:shop, owner: user) }

  it "is Me by default" do
    expect(user.selling_shop).to be_nil
  end

  it "switches to a shop the user is a member of, and back to Me" do
    expect(user.sell_as!(shop)).to be(true)
    expect(user.reload.selling_shop).to eq(shop)
    expect(user.sell_as!(nil)).to be(true)
    expect(user.reload.selling_shop).to be_nil
  end

  it "refuses a shop the user is not in" do
    expect(user.sell_as!(create(:shop))).to be(false)
    expect(user.reload.active_shop_id).to be_nil
  end

  it "falls back to Me when the membership is gone" do
    user.sell_as!(shop)
    shop.shop_members.where(user: user).delete_all
    expect(user.reload.selling_shop).to be_nil
    expect(user.reload.active_shop_id).to be_nil
  end

  it "falls back to Me when the shop is suspended" do
    user.sell_as!(shop)
    shop.suspended!
    expect(user.reload.selling_shop).to be_nil
  end

  describe "#listings_for_selling_identity" do
    it "is the shop's products as the shop, and the personal ones as Me" do
      personal = create(:listing, user: user)
      in_shop = create(:listing, user: user, shop: shop)
      expect(user.listings_for_selling_identity).to contain_exactly(personal)
      user.sell_as!(shop)
      expect(user.reload.listings_for_selling_identity).to contain_exactly(in_shop)
    end
  end
end

RSpec.describe User, "#unread_counts" do
  let(:user) { create(:user) }
  let(:shop) { create(:shop, owner: user) }

  def unread_in(conversation, from:, n: 1)
    n.times { create(:message, conversation: conversation, user: from, read_at: nil) }
  end

  it "splits unread messages by identity, in one query" do
    buying = create(:conversation, buyer: user)
    selling_me = create(:conversation, listing: create(:listing, :active, user: user))
    selling_shop = create(:conversation, listing: create(:listing, :active, user: user, shop: shop))
    unread_in(buying, from: buying.seller, n: 2)
    unread_in(selling_me, from: selling_me.buyer)
    unread_in(selling_shop, from: selling_shop.buyer, n: 3)
    create(:message, conversation: selling_shop, user: user, read_at: nil) # my own message never counts

    queries = 0
    counts = ActiveSupport::Notifications.subscribed(->(*) { queries += 1 }, "sql.active_record") { user.unread_counts }
    expect(counts).to eq(buying: 2, selling_me: 1, support: 0, shops: { shop.id.to_s => 3 })
    expect(queries).to eq(1)
  end

  it "is all zeros for a user with nothing unread" do
    expect(user.unread_counts).to eq(buying: 0, selling_me: 0, support: 0, shops: {})
  end

  # Owner, 2026-10-12: Support per identity. The person's own thread is shown in
  # Buyer mode and Seller as Me (so it is in `buying` and in `support`); a
  # shop's own thread counts only in that shop's entry.
  it "counts the person's Support thread as support (and buying), a shop's thread in the shop" do
    support = User.support_account!
    unread_in(Conversation.support_thread_for!(user), from: support, n: 2)
    unread_in(Conversation.shop_support_thread_for!(shop), from: support)
    expect(user.unread_counts).to eq(buying: 2, selling_me: 0, support: 2, shops: { shop.id.to_s => 1 })
  end
end
