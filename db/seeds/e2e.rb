# =============================================================================
# Hatiwal E2E Test Seeds
#
# Creates a known, stable dataset for Maestro E2E tests.
# Safe to re-run — idempotent via find_or_initialize_by.
#
# Run:  bundle exec rails db:seed:e2e
#
# Test accounts (password: Password123!):
#   buyer@hatiwal.test    — buyer with saved listings + 1 conversation
#   seller@hatiwal.test   — seller with draft / active / reserved listings
#   newbuyer@hatiwal.test — fresh account, nothing saved, no history
# =============================================================================

puts "=== E2E Seed: Users ==="

def e2e_user(email:, firstname:, lastname:, city:, province:)
  user = User.find_or_initialize_by(email: email)
  unless user.persisted?
    user.assign_attributes(
      firstname:             firstname,
      lastname:              lastname,
      password:              "Password123!",
      password_confirmation: "Password123!",
      city:                  city,
      province:              province,
      phone:                 "+93700000#{rand(100..999)}",
      bio:                   "E2E test account.",
      preferred_language:    "en",
      preferred_theme:       "system",
      uid:                   email,
      provider:              "email"
    )
    user.skip_confirmation!
    user.save!
    puts "  created #{email}"
  else
    puts "  exists  #{email}"
  end
  user
end

buyer    = e2e_user(email: "buyer@hatiwal.test",    firstname: "Ahmad",   lastname: "Karimi",  city: "Kabul",     province: "Kabul")
seller   = e2e_user(email: "seller@hatiwal.test",   firstname: "Omar",    lastname: "Noori",   city: "Kandahar",  province: "Kandahar")
newbuyer = e2e_user(email: "newbuyer@hatiwal.test", firstname: "Fatima",  lastname: "Rahimi",  city: "Herat",     province: "Herat")

# =============================================================================
puts "=== E2E Seed: Categories (ensure electronics exists) ==="
# =============================================================================

electronics = Category.find_or_create_by!(slug: "electronics") do |c|
  c.name_en = "Electronics"
  c.name_ps = "برقی وسایل"
  c.name_fa = "وسایل برقی"
  c.icon     = "📱"
  c.position = 1
  c.active   = true
end

clothes = Category.find_or_create_by!(slug: "clothes") do |c|
  c.name_en = "Clothes & Fashion"
  c.name_ps = "کالي او فیشن"
  c.name_fa = "لباس و مد"
  c.icon     = "👗"
  c.position = 2
  c.active   = true
end

vehicles = Category.find_or_create_by!(slug: "vehicles") do |c|
  c.name_en = "Vehicles"
  c.name_ps = "موټرونه"
  c.name_fa = "وسایل نقلیه"
  c.icon     = "🚗"
  c.position = 3
  c.active   = true
end

home = Category.find_or_create_by!(slug: "home") do |c|
  c.name_en = "Home & Furniture"
  c.name_ps = "کور او فرنیچر"
  c.name_fa = "خانه و مبلمان"
  c.icon     = "🏠"
  c.position = 4
  c.active   = true
end

puts "  categories ready"

# =============================================================================
puts "=== E2E Seed: Seller Listings ==="
# =============================================================================

def e2e_listing(user:, title:, price:, category:, status:, description:, location:)
  return if Listing.exists?(user: user, title: title)

  attrs = {
    user:        user,
    category:    category,
    title:       title,
    description: description,
    price:       price,
    currency:    "AFN",
    status:      status,
    location:    location,
    views_count: rand(5..200)
  }

  attrs[:published_at] = rand(1..30).days.ago if %i[active reserved sold].include?(status)
  attrs[:reserved_at]  = rand(1..7).days.ago   if status == :reserved
  attrs[:sold_at]      = rand(1..14).days.ago  if status == :sold

  Listing.create!(attrs)
  puts "  created listing [#{status}] #{title}"
end

# Draft listings — for create/edit/delete/publish flow tests
e2e_listing(
  user:        seller,
  title:       "iPhone 12 Pro - 128GB",
  price:       25_000,
  category:    electronics,
  status:      :draft,
  description: "Good condition, no scratches. Comes with original charger and box.",
  location:    "Kandahar, City Center"
)

e2e_listing(
  user:        seller,
  title:       "Samsung Galaxy S21 256GB",
  price:       32_000,
  category:    electronics,
  status:      :draft,
  description: "Used 8 months. Battery health 91%. Original accessories included.",
  location:    "Kandahar"
)

# Active listings — for browse, reserve, report, save, message tests
e2e_listing(
  user:        seller,
  title:       "Toyota Corolla 2016 Automatic",
  price:       1_350_000,
  category:    vehicles,
  status:      :active,
  description: "Single owner. 90,000 km. Full service history. AC works perfectly. Clean.",
  location:    "Kandahar, Main Road"
)

e2e_listing(
  user:        seller,
  title:       "Lenovo ThinkPad Laptop Core i5 8GB",
  price:       38_000,
  category:    electronics,
  status:      :active,
  description: "11th Gen Core i5, 8GB RAM, 256GB SSD. Excellent for work and dev. Charger included.",
  location:    "Kandahar"
)

e2e_listing(
  user:        seller,
  title:       "Traditional Kandahari Carpet 3x4",
  price:       28_000,
  category:    home,
  status:      :active,
  description: "Handwoven Kandahari carpet. Rich colors. No tears. Great for living room.",
  location:    "Kandahar, Old Bazaar"
)

e2e_listing(
  user:        seller,
  title:       "Men Winter Jacket XL Black",
  price:       3_500,
  category:    clothes,
  status:      :active,
  description: "Thick and warm. Worn twice. Excellent condition. Size XL.",
  location:    "Kandahar"
)

# Reserved listing — for lifecycle reactivate test
e2e_listing(
  user:        seller,
  title:       "Honda CG 125 Motorbike 2022",
  price:       90_000,
  category:    vehicles,
  status:      :reserved,
  description: "Low mileage. Red color. Registration done. Comes with extra parts.",
  location:    "Kandahar"
)

# Sold listing — shows up in sold filter
e2e_listing(
  user:        seller,
  title:       "Xiaomi Redmi Note 11 128GB",
  price:       14_000,
  category:    electronics,
  status:      :sold,
  description: "6GB RAM. 50MP camera. Sold as-is.",
  location:    "Kandahar"
)

# =============================================================================
puts "=== E2E Seed: Price-Drop History ==="
# =============================================================================
# Attach a recent price-drop history to one active seller listing so that the
# Maestro price-drop badge tests can make non-optional assertions.
# We use the Lenovo ThinkPad (38 000 AFN → 32 300 AFN = ~15% drop).
# Idempotent: skip if a recent reduction record already exists for this listing.

price_drop_listing = Listing.find_by(user: seller, title: "Lenovo ThinkPad Laptop Core i5 8GB")

if price_drop_listing
  # True idempotency: gate on ANY reduction for this listing ever, not just the
  # last 14 days.  Using .recent(14) would cause re-seeds after 14 days.
  already_seeded = ListingPriceHistory
    .where(listing: price_drop_listing)
    .reductions
    .exists?

  unless already_seeded
    ListingPriceHistory.create!(
      listing:    price_drop_listing,
      old_price:  38_000,
      new_price:  32_300,
      currency:   "AFN",
      changed_at: 2.days.ago
    )
    puts "  price-drop history created: Lenovo ThinkPad (38 000 → 32 300 AFN, ~15%)"
  else
    puts "  price-drop history already present for Lenovo ThinkPad"
  end
else
  puts "  WARN: Lenovo ThinkPad listing not found — price-drop seed skipped"
end

# =============================================================================
puts "=== E2E Seed: Buyer Saved Listings ==="
# =============================================================================

seller_active = Listing.where(user: seller, status: :active).to_a

seller_active.first(2).each do |listing|
  next if SavedListing.exists?(user: buyer, listing: listing)
  SavedListing.create!(user: buyer, listing: listing)
  puts "  buyer saved: #{listing.title}"
end

# =============================================================================
puts "=== E2E Seed: Buyer Conversations (response-rate badge threshold) ==="
# =============================================================================
# TASK-N805: The seller response-rate badge requires >= 5 conversations in the
# last 90 days.  We seed 6 conversations so the badge is guaranteed to render
# in all Maestro E2E tests.  Each conversation has a quick seller reply
# (< 30 min) so the time-label comes out as :within_one_hour.

target_listing = Listing.find_by(user: seller, title: "Lenovo ThinkPad Laptop Core i5 8GB")

# Extra synthetic buyers — idempotent via find_or_initialize_by
e2e_extra_buyers = [
  { email: "e2ebuyer2@hatiwal.test", firstname: "Bilal",  lastname: "Khan" },
  { email: "e2ebuyer3@hatiwal.test", firstname: "Roya",   lastname: "Nazari" },
  { email: "e2ebuyer4@hatiwal.test", firstname: "Yusuf",  lastname: "Haidari" },
  { email: "e2ebuyer5@hatiwal.test", firstname: "Laila",  lastname: "Ghafari" },
  { email: "e2ebuyer6@hatiwal.test", firstname: "Jawad",  lastname: "Siddiqui" }
].map do |attrs|
  u = User.find_or_initialize_by(email: attrs[:email])
  unless u.persisted?
    u.assign_attributes(
      firstname: attrs[:firstname], lastname: attrs[:lastname],
      password: "Password123!", password_confirmation: "Password123!",
      city: "Kabul", province: "Kabul", preferred_language: "en",
      preferred_theme: "system", uid: attrs[:email], provider: "email"
    )
    u.skip_confirmation!
    u.save!
    puts "  created e2e buyer: #{attrs[:email]}"
  end
  u
end

# All 6 buyers: original buyer + 5 extra
all_buyers = [ buyer ] + e2e_extra_buyers

RESPONSE_BADGE_CONVOS = [
  { buyer_msg: "Hi, is this laptop still available?",               seller_reply: "Yes it is! Come check it anytime.",            days_ago: 3 },
  { buyer_msg: "What is the lowest price you can do?",              seller_reply: "I can do a small discount for cash today.",     days_ago: 8 },
  { buyer_msg: "Can we meet tomorrow in Kandahar city?",            seller_reply: "Sure, how about 10am near the main bazaar?",   days_ago: 15 },
  { buyer_msg: "Is the original charger included?",                 seller_reply: "Yes, original charger and box both included.", days_ago: 22 },
  { buyer_msg: "How is the battery? Does it hold charge well?",     seller_reply: "Battery is great, holds full charge all day.", days_ago: 29 },
  { buyer_msg: "Can I see more photos before I come?",              seller_reply: "Of course, sending more photos right now.",    days_ago: 36 }
].freeze

if target_listing
  RESPONSE_BADGE_CONVOS.each_with_index do |data, idx|
    convo_buyer = all_buyers[idx]
    next if Conversation.exists?(listing: target_listing, buyer: convo_buyer)

    base_time = data[:days_ago].days.ago
    convo = Conversation.create!(listing: target_listing, buyer: convo_buyer, seller: seller)

    # Buyer opens with a question
    bm = Message.new(conversation: convo, user: convo_buyer, body: data[:buyer_msg], kind: :text,
                     read_at: base_time + 2.minutes)
    bm.created_at = base_time
    bm.updated_at = base_time
    bm.save!

    # Seller replies within 30 minutes — qualifies as within-1-hour response
    sr = Message.new(conversation: convo, user: seller, body: data[:seller_reply], kind: :text,
                     read_at: base_time + 45.minutes)
    sr.created_at = base_time + 30.minutes
    sr.updated_at = base_time + 30.minutes
    sr.save!

    convo.update!(last_message_at: base_time + 30.minutes)
    puts "  seeded response-badge conversation #{idx + 1}/#{RESPONSE_BADGE_CONVOS.size}"
  end
  puts "  seller@hatiwal.test now has >= 5 conversations — response-rate badge will render"
else
  puts "  WARN: Lenovo ThinkPad listing not found — response-rate seed skipped"
end

# =============================================================================
puts ""
puts "======================================"
puts "  E2E SEED COMPLETE"
puts "======================================"
puts ""
puts "  Test accounts (password: Password123!)"
puts "  buyer@hatiwal.test    — buyer with 2 saved listings + conversations"
puts "  seller@hatiwal.test   — seller with #{Listing.where(user: seller).count} listings"
puts "    draft:    #{Listing.where(user: seller, status: :draft).count}"
puts "    active:   #{Listing.where(user: seller, status: :active).count}"
puts "    reserved: #{Listing.where(user: seller, status: :reserved).count}"
puts "    sold:     #{Listing.where(user: seller, status: :sold).count}"
puts "    convos:   #{Conversation.where(seller: seller).count} (response-rate badge: #{Conversation.where(seller: seller).count >= 5 ? 'YES' : 'NO — needs >=5'})"
puts "  newbuyer@hatiwal.test — fresh account, nothing saved"
puts ""
puts "  Run E2E tests: maestro test hatiwal-mobile/maestro/"
puts "======================================"
