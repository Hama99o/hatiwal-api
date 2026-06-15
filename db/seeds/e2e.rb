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
puts "=== E2E Seed: Buyer Saved Listings ==="
# =============================================================================

seller_active = Listing.where(user: seller, status: :active).to_a

seller_active.first(2).each do |listing|
  next if SavedListing.exists?(user: buyer, listing: listing)
  SavedListing.create!(user: buyer, listing: listing)
  puts "  buyer saved: #{listing.title}"
end

# =============================================================================
puts "=== E2E Seed: Buyer Conversation ==="
# =============================================================================

target_listing = Listing.find_by(user: seller, title: "Lenovo ThinkPad Laptop Core i5 8GB")

if target_listing && !Conversation.exists?(listing: target_listing, buyer: buyer)
  convo = Conversation.create!(
    listing: target_listing,
    buyer:   seller,    # seller is seller, buyer is buyer
    seller:  seller
  )

  # Rebuild with correct buyer
  convo.destroy
  convo = Conversation.create!(
    listing: target_listing,
    buyer:   buyer,
    seller:  seller
  )

  messages = [
    { sender: buyer,  body: "Hi, is this laptop still available?",                   time: 3.days.ago },
    { sender: seller, body: "Yes it is! Come check it anytime.",                     time: 3.days.ago + 5.minutes },
    { sender: buyer,  body: "Great. Can we meet tomorrow morning in Kandahar city?", time: 3.days.ago + 20.minutes },
    { sender: seller, body: "Sure, how about 10am near the main bazaar?",            time: 3.days.ago + 35.minutes },
    { sender: buyer,  body: "Perfect, see you then 🙏",                              time: 3.days.ago + 50.minutes }
  ]

  messages.each_with_index do |m, i|
    msg = Message.new(
      conversation: convo,
      user:         m[:sender],
      body:         m[:body],
      kind:         :text,
      read_at:      i < messages.length - 1 ? m[:time] + 2.minutes : nil
    )
    msg.created_at = m[:time]
    msg.updated_at = m[:time]
    msg.save!
  end

  convo.update!(last_message_at: messages.last[:time])
  puts "  created conversation: buyer ↔ seller (Lenovo ThinkPad)"
end

# =============================================================================
puts ""
puts "======================================"
puts "  E2E SEED COMPLETE"
puts "======================================"
puts ""
puts "  Test accounts (password: Password123!)"
puts "  buyer@hatiwal.test    — buyer with 2 saved listings + 1 conversation"
puts "  seller@hatiwal.test   — seller with #{Listing.where(user: seller).count} listings"
puts "    draft:    #{Listing.where(user: seller, status: :draft).count}"
puts "    active:   #{Listing.where(user: seller, status: :active).count}"
puts "    reserved: #{Listing.where(user: seller, status: :reserved).count}"
puts "    sold:     #{Listing.where(user: seller, status: :sold).count}"
puts "  newbuyer@hatiwal.test — fresh account, nothing saved"
puts ""
puts "  Run E2E tests: maestro test hatiwal-mobile/maestro/"
puts "======================================"
