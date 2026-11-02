require "rails_helper"

# Performance pass 1.1.6 (d0, 2026-10-08): the read paths production runs most,
# each measured at N = 1 and N = 20 items. A query count that grows with N is an
# N+1. Every item has its OWN user / shop / logo / image, so Rails' per-request
# identity map cannot hide a per-row query behind a shared record.
RSpec.describe "1.1.6 read paths — query counts do not grow with N", type: :request do
  IMG = Rails.root.join("spec/fixtures/files/test_image.jpg")

  def count_queries
    count = 0
    subscriber = lambda do |*, payload|
      sql = payload[:sql].to_s
      next if sql.start_with?("SAVEPOINT", "RELEASE SAVEPOINT", "ROLLBACK TO SAVEPOINT")
      next if sql.match?(/\AUPDATE "users" SET "tokens"/)
      next if payload[:name] == "SCHEMA"

      count += 1
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    count
  end

  def h(user) = auth_headers_for(user)
  def with_avatar(user) = user.tap { |u| u.avatar.attach(io: File.open(IMG), filename: "a.jpg", content_type: "image/jpeg") }

  def shop_with_logo(owner = create(:user))
    create(:shop, owner: owner).tap { |s| s.logo.attach(io: File.open(IMG), filename: "l.jpg", content_type: "image/jpeg") }
  end

  def product(shop, by: shop.owner) = create(:listing, :active, :with_image, user: by, shop: shop)

  # Measure the same request at N = 1 and N = 20; `build.(n)` returns a proc
  # that performs the request. Setup — the auth headers included (creating a
  # token reads the user) — stays outside the counted block.
  def measure(build)
    small = build.call(1)
    big = build.call(20)
    [ count_queries { small.call }, count_queries { big.call } ]
  end

  RESULTS = {}

  after(:all) do
    width = RESULTS.keys.map(&:size).max.to_i
    puts "\n#{'path'.ljust(width)}  N=1  N=20"
    RESULTS.each { |path, (a, b)| puts "#{path.ljust(width)}  #{a.to_s.rjust(3)}  #{b.to_s.rjust(4)}#{'  <-- grows' if b > a}" }
  end

  def record(label, counts)
    RESULTS[label] = counts
    expect(counts.last).to eq(counts.first), "#{label}: #{counts.first} queries at N=1, #{counts.last} at N=20"
  end

  it "the buyer's inbox: N chats with N different shops (logos, team replies)" do
    record("GET /conversations (buyer, shop chats)", measure(lambda do |n|
      buyer = with_avatar(create(:user))
      n.times do
        shop = shop_with_logo
        staff = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
        chat = Conversations::StartService.new(buyer: buyer, listing: product(shop), message_body: "Hi").call
        chat.messages.create!(user: staff, kind: :text, body: "Yes")
      end
      hd = h(buyer)
      -> { get "/api/v1/conversations", headers: hd }
    end))
  end

  it "the shop's inbox (a member, shop selected): N chats with N buyers" do
    record("GET /conversations?shop_id= (team)", measure(lambda do |n|
      shop = shop_with_logo
      staff = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
      n.times do
        buyer = with_avatar(create(:user))
        chat = Conversations::StartService.new(buyer: buyer, listing: product(shop), message_body: "Hi").call
        chat.messages.create!(user: staff, kind: :text, body: "Yes")
      end
      hd = h(staff)
      -> { get "/api/v1/conversations", params: { role: "selling", shop_id: shop.id }, headers: hd }
    end))
  end

  it "unread_counts on /users/me: N identities (shops) with unread chats" do
    record("GET /users/me (N shops + unread + invites)", measure(lambda do |n|
      me = create(:user)
      n.times do
        shop = shop_with_logo
        shop.shop_members.create!(user: me, role: :staff)
        Conversations::StartService.new(buyer: create(:user), listing: product(shop), message_body: "Hi").call
        create(:shop_invite, shop: shop_with_logo, email: me.email) rescue nil
      end
      hd = h(me)
      -> { get "/api/v1/users/me", headers: hd }
    end))
  end

  it "a thread's messages: N messages from N team members, as the team" do
    record("GET /conversations/:id/messages (team)", measure(lambda do |n|
      shop = shop_with_logo
      buyer = with_avatar(create(:user))
      chat = Conversations::StartService.new(buyer: buyer, listing: product(shop), message_body: "Hi").call
      n.times do
        member = with_avatar(create(:user)).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
        chat.messages.create!(user: member, kind: :text, body: "Reply")
      end
      hd = h(shop.owner)
      -> { get "/api/v1/conversations/#{chat.id}/messages", headers: hd }
    end))
  end

  it "the shop page and its products: N products posted by N members" do
    record("GET /shops/:id", measure(lambda do |n|
      shop = shop_with_logo
      n.times do
        member = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
        product(shop, by: member)
      end
      hd = h(create(:user))
      -> { get "/api/v1/shops/#{shop.id}", headers: hd }
    end))
    record("GET /listings?shop_id= (shop products)", measure(lambda do |n|
      shop = shop_with_logo
      n.times do
        member = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
        product(shop, by: member)
      end
      hd = h(create(:user))
      -> { get "/api/v1/listings", params: { shop_id: shop.id }, headers: hd }
    end))
  end

  it "the feed with shop faces: N products of N shops" do
    record("GET /listings (feed, shop faces)", measure(lambda do |n|
      Listing.update_all(removed_at: Time.current)
      n.times { product(shop_with_logo) }
      viewer = create(:user)
      hd = h(viewer)
      -> { get "/api/v1/listings", headers: hd }
    end))
  end

  it "my/listings as a member of a shop: N products with expiry, posted by N members" do
    record("GET /my/listings (shop selected)", measure(lambda do |n|
      shop = shop_with_logo
      me = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :manager) }
      me.update_columns(active_shop_id: shop.id)
      n.times do
        member = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
        product(shop, by: member)
      end
      hd = h(me)
      -> { get "/api/v1/my/listings", headers: hd }
    end))
  end

  it "analytics of a shop: N members with their numbers" do
    record("GET /my/analytics?shop_id=", measure(lambda do |n|
      shop = shop_with_logo
      n.times do
        member = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
        product(shop, by: member)
      end
      hd = h(shop.owner)
      -> { get "/api/v1/my/analytics", params: { shop_id: shop.id }, headers: hd }
    end))
  end
end
