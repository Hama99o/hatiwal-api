require "rails_helper"

# The "Unread messages" divider (TASK-D428) could never render on any thread,
# because `unread_count` was defined only in the :list view while
# `GET /conversations/:id` renders :detailed. The client read the missing key as
# 0 (`?? 0`), resolveUnreadBoundaryId returns null for 0, and no divider was ever
# emitted.
#
# Found 2026-09-02 by chat/mark_read_end_to_end. Worth specs on BOTH views,
# because the bug was not a wrong value — it was a field that existed in one
# view and not the other, which no assertion about :list could ever catch.
RSpec.describe ConversationSerializer, "unread_count" do
  let(:buyer)  { create(:user) }
  let(:seller) { create(:user) }
  let(:conversation) do
    create(:conversation, buyer: buyer, seller: seller,
                          listing: create(:listing, user: seller))
  end

  def render(view, user: buyer, **opts)
    described_class.render_as_hash(conversation, view: view, current_user: user, **opts)
  end

  before do
    create(:message, conversation: conversation, user: buyer,  body: "mine",  read_at: Time.current)
    create(:message, conversation: conversation, user: seller, body: "theirs", read_at: nil)
  end

  it "is present in :detailed — the view the THREAD screen fetches" do
    expect(render(:detailed)).to have_key(:unread_count)
  end

  it "is present in :list — the view the inbox fetches" do
    expect(render(:list)).to have_key(:unread_count)
  end

  it "counts an inbound unread message in both views" do
    expect(render(:detailed)[:unread_count]).to eq(1)
    expect(render(:list)[:unread_count]).to eq(1)
  end

  it "does not count the viewer's OWN unread messages" do
    create(:message, conversation: conversation, user: buyer, body: "also mine", read_at: nil)
    expect(render(:detailed)[:unread_count]).to eq(1)
  end

  it "counts from the SELLER's side independently" do
    # The seller's own message is outbound for them; the buyer's read one is not
    # unread either.
    expect(render(:detailed, user: seller)[:unread_count]).to eq(0)
  end

  it "is 0 with no current_user rather than raising" do
    expect(described_class.render_as_hash(conversation, view: :detailed)[:unread_count]).to eq(0)
  end

  it "uses the controller's precomputed counts when given them" do
    # The index passes a hash to avoid one COUNT per row; the fallback must not
    # silently disagree with it.
    hash = { conversation.id => 7 }
    expect(render(:list, unread_counts: hash)[:unread_count]).to eq(7)
    expect(render(:detailed, unread_counts: hash)[:unread_count]).to eq(7)
  end

  it "falls back to the model when no precomputed hash is passed — the `show` path" do
    expect(render(:detailed)[:unread_count]).to eq(conversation.unread_count_for(buyer))
  end
end
