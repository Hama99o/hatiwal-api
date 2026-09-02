require "rails_helper"

# Owner, 2026-09-02: "I saw the message conversation search is not working, like
# it's not connected with backend, it's not search in db. It's important, check
# if I am right."
#
# He was right. The clients filtered already-loaded items in memory, so anything
# past the first page could not be found, and the UI shipped a string saying so
# ("Showing results in loaded conversations only"). These specs pin the
# server-side behaviour, including the case that proves the point: a match that
# is NOT on the first page.
RSpec.describe "conversation search", type: :request do
  let(:me)    { create(:user, firstname: "Mine", lastname: "Self") }
  let(:other) { create(:user, firstname: "Zarmina", lastname: "Hakimi") }

  def ids
    JSON.parse(response.body)["conversations"].map { |c| c["id"] }
  end

  it "finds a thread by the OTHER PARTY's name" do
    c = create(:conversation, buyer: me, seller: other,
                              listing: create(:listing, user: other, title: "Bicycle"))
    get "/api/v1/conversations", params: { search: "zarmina" }, headers: auth_headers_for(me)
    expect(ids).to include(c.id)
  end

  it "finds a thread by the LISTING's title" do
    c = create(:conversation, buyer: me, seller: other,
                              listing: create(:listing, user: other, title: "Wool Blanket"))
    get "/api/v1/conversations", params: { search: "blanket" }, headers: auth_headers_for(me)
    expect(ids).to include(c.id)
  end

  it "finds a thread by the TEXT OF A MESSAGE inside it" do
    c = create(:conversation, buyer: me, seller: other,
                              listing: create(:listing, user: other, title: "Bicycle"))
    create(:message, conversation: c, user: other, body: "I can meet at Shahr-e-Naw")
    get "/api/v1/conversations", params: { search: "shahr-e-naw" }, headers: auth_headers_for(me)
    expect(ids).to include(c.id)
  end

  it "is case-insensitive" do
    c = create(:conversation, buyer: me, seller: other,
                              listing: create(:listing, user: other, title: "Wool Blanket"))
    get "/api/v1/conversations", params: { search: "WOOL" }, headers: auth_headers_for(me)
    expect(ids).to include(c.id)
  end

  it "FINDS A MATCH THAT IS NOT ON THE FIRST PAGE — the whole point" do
    # 25 decoys, then the target as the OLDEST thread, so with any sane page size
    # it cannot be in the client's loaded set.
    25.times do |i|
      create(:conversation, buyer: me, seller: create(:user),
                            listing: create(:listing, title: "Decoy #{i}"),
                            last_message_at: (i + 2).minutes.ago)
    end
    target = create(:conversation, buyer: me, seller: other,
                                   listing: create(:listing, user: other, title: "Kandahari Rug"),
                                   last_message_at: 10.days.ago)

    get "/api/v1/conversations",
        params: { search: "kandahari", "page[size]" => 10 },
        headers: auth_headers_for(me)
    expect(ids).to include(target.id)
  end

  it "returns a thread with NO messages yet when its listing matches" do
    # left_joins, not joins — a brand-new thread must not vanish from its own
    # search results.
    c = create(:conversation, buyer: me, seller: other,
                              listing: create(:listing, user: other, title: "Empty Thread Item"))
    expect(c.messages).to be_empty
    get "/api/v1/conversations", params: { search: "empty thread" }, headers: auth_headers_for(me)
    expect(ids).to include(c.id)
  end

  it "returns no duplicates when several messages match" do
    c = create(:conversation, buyer: me, seller: other,
                              listing: create(:listing, user: other, title: "Bicycle"))
    3.times { create(:message, conversation: c, user: other, body: "bicycle please") }
    get "/api/v1/conversations", params: { search: "bicycle" }, headers: auth_headers_for(me)
    expect(ids.count(c.id)).to eq(1)
  end

  it "never returns someone else's conversation" do
    stranger = create(:user)
    theirs = create(:conversation, buyer: stranger, seller: other,
                                   listing: create(:listing, user: other, title: "Wool Blanket"))
    get "/api/v1/conversations", params: { search: "blanket" }, headers: auth_headers_for(me)
    expect(ids).not_to include(theirs.id)
  end

  it "ignores a blank search rather than returning nothing" do
    c = create(:conversation, buyer: me, seller: other, listing: create(:listing, user: other))
    get "/api/v1/conversations", params: { search: "   " }, headers: auth_headers_for(me)
    expect(ids).to include(c.id)
  end

  it "treats LIKE wildcards as literal text, not as a pattern" do
    create(:conversation, buyer: me, seller: other,
                          listing: create(:listing, user: other, title: "Wool Blanket"))
    get "/api/v1/conversations", params: { search: "%" }, headers: auth_headers_for(me)
    # A bare % must not match everything.
    expect(ids).to be_empty
  end
end
