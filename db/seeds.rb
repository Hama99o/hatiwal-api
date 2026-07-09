# =============================================================================
# Hatiwal Seeds — deep development data
# Run: rails db:seed  (idempotent — safe to re-run)
# =============================================================================

# ── Admin account ────────────────────────────────────────────────────────────
# Staff login for the /admin dashboard. Credentials come from ENV so production
# never ships a known password. In production ADMIN_PASSWORD is REQUIRED — the
# seed fails loudly rather than provisioning an admin with a committed default.
# The weak fallback exists only for development/test convenience.
puts "=== Seeding Admin user ==="
admin_email    = ENV.fetch("ADMIN_EMAIL", "admin@hatiwal.com")
admin_password = ENV.fetch("ADMIN_PASSWORD") do
  if Rails.env.production?
    raise "ADMIN_PASSWORD must be set to seed the admin user in production — refusing to create an admin with a known default password."
  end

  "changeme123!" # development/test only — never reaches production (guard above)
end
admin = AdminUser.find_or_initialize_by(email: admin_email)
if admin.new_record?
  admin.name     = ENV.fetch("ADMIN_NAME", "Hatiwal Admin")
  admin.password = admin_password
  admin.save!
  puts "  created admin: #{admin_email}"
else
  puts "  admin already exists: #{admin_email}"
end

puts "=== Seeding Categories ==="

TOP_LEVEL_CATEGORIES = [
  { name_en: "Electronics",        name_ps: "برقی وسایل",        name_fa: "وسایل برقی",                slug: "electronics", icon: "📱", position: 1  },
  { name_en: "Clothes & Fashion",   name_ps: "کالي او فیشن",      name_fa: "لباس و مد",                 slug: "clothes",     icon: "👗", position: 2  },
  { name_en: "Vehicles",            name_ps: "موټرونه",            name_fa: "وسایل نقلیه",               slug: "vehicles",    icon: "🚗", position: 3  },
  { name_en: "Home & Furniture",    name_ps: "کور او فرنیچر",     name_fa: "خانه و مبلمان",              slug: "home",        icon: "🏠", position: 4  },
  { name_en: "Books & Education",   name_ps: "کتابونه",            name_fa: "کتاب و آموزش",              slug: "books",       icon: "📚", position: 5  },
  { name_en: "Food & Agriculture",  name_ps: "خواړه او کرنه",     name_fa: "مواد غذایی و کشاورزی",      slug: "food",        icon: "🌾", position: 6  },
  { name_en: "Tools & Equipment",   name_ps: "وسایل او تجهیزات",  name_fa: "ابزار و تجهیزات",           slug: "tools",       icon: "🔧", position: 7  },
  { name_en: "Sports & Outdoors",   name_ps: "سپورت او بهرني",   name_fa: "ورزش و فضای باز",            slug: "sports",      icon: "⚽", position: 8  },
  { name_en: "Beauty & Health",     name_ps: "ښایست او روغتیا",  name_fa: "زیبایی و بهداشت",            slug: "beauty",      icon: "💄", position: 9  },
  { name_en: "Bags & Accessories",  name_ps: "بیگونه او اکسیسوریز", name_fa: "کیف و لوازم",             slug: "bags",        icon: "👜", position: 10 },
  { name_en: "Kids & Toys",         name_ps: "د ماشومانو توکي",  name_fa: "کودک و اسباب‌بازی",          slug: "kids",        icon: "🧸", position: 11 },
  { name_en: "Property",            name_ps: "ملکیت",              name_fa: "ملک",                        slug: "property",    icon: "🏗️", position: 12 },
  { name_en: "Jobs",                name_ps: "دندې",               name_fa: "کار",                        slug: "jobs",        icon: "💼", position: 13 },
  { name_en: "Services",            name_ps: "خدمتونه",            name_fa: "خدمات",                     slug: "services",    icon: "🛠️", position: 14 },
  { name_en: "Other",               name_ps: "نور",                name_fa: "دیگر",                       slug: "other",       icon: "📦", position: 15 }
].freeze

# Remove the old "Animals" top-level if it exists (it becomes a subcategory of Food)
animals_top_level = Category.find_by(slug: "animals", parent_id: nil)
if animals_top_level
  # Reassign any listings that belong to the top-level animals category
  # They will stay under animals_top_level for now; we re-parent them after creating the livestock subcat
  puts "  Found top-level 'animals' category — will convert to subcategory of 'food'"
end

TOP_LEVEL_CATEGORIES.each do |attrs|
  cat = Category.find_or_initialize_by(slug: attrs[:slug])
  cat.assign_attributes(attrs.merge(parent_id: nil))
  cat.active = true unless cat.persisted?
  cat.save!
end

puts "  Top-level categories seeded"

# =============================================================================
# Subcategories
# =============================================================================

SUBCATEGORIES = [
  # Electronics
  { parent_slug: "electronics", name_en: "Phones & Tablets",      name_ps: "موبایلونه او تبلیټونه", name_fa: "گوشی و تبلت",        slug: "phones",             icon: "📱", position: 1 },
  { parent_slug: "electronics", name_en: "Computers & Laptops",   name_ps: "کمپیوترونه",            name_fa: "کامپیوتر و لپ‌تاپ", slug: "computers",          icon: "💻", position: 2 },
  { parent_slug: "electronics", name_en: "TVs & Audio",           name_ps: "ټلویزیونونه او سوند",  name_fa: "تلویزیون و صدا",     slug: "tv-audio",           icon: "📺", position: 3 },
  { parent_slug: "electronics", name_en: "Cameras",               name_ps: "کیمرې",                 name_fa: "دوربین",              slug: "cameras",            icon: "📷", position: 4 },
  { parent_slug: "electronics", name_en: "Accessories",           name_ps: "اکسیسوریز",             name_fa: "لوازم جانبی",        slug: "tech-accessories",   icon: "🎧", position: 5 },

  # Clothes & Fashion
  { parent_slug: "clothes", name_en: "Men's Clothing",        name_ps: "مردانه کالي",       name_fa: "لباس مردانه",      slug: "mens-clothing",      icon: "👔", position: 1 },
  { parent_slug: "clothes", name_en: "Women's Clothing",      name_ps: "زنانه کالي",        name_fa: "لباس زنانه",       slug: "womens-clothing",    icon: "👗", position: 2 },
  { parent_slug: "clothes", name_en: "Children's Clothing",   name_ps: "د اطفالو کالي",    name_fa: "لباس اطفال",       slug: "kids-clothing",      icon: "👶", position: 3 },
  { parent_slug: "clothes", name_en: "Traditional Clothing",  name_ps: "دودیز کالي",        name_fa: "لباس سنتی",        slug: "traditional-clothing", icon: "🧕", position: 4 },
  { parent_slug: "clothes", name_en: "Shoes",                 name_ps: "بوټان",              name_fa: "کفش",              slug: "shoes",              icon: "👟", position: 5 },

  # Vehicles
  { parent_slug: "vehicles", name_en: "Cars",          name_ps: "موټرونه",        name_fa: "خودرو",         slug: "cars",           icon: "🚗", position: 1 },
  { parent_slug: "vehicles", name_en: "Motorcycles",   name_ps: "موټرسایکلونه",  name_fa: "موتورسیکلت",   slug: "motorcycles",    icon: "🏍️", position: 2 },
  { parent_slug: "vehicles", name_en: "Bicycles",      name_ps: "سایکلونه",       name_fa: "دوچرخه",        slug: "bicycles",       icon: "🚲", position: 3 },
  { parent_slug: "vehicles", name_en: "Spare Parts",   name_ps: "پرزې",           name_fa: "قطعات",         slug: "vehicle-parts",  icon: "⚙️", position: 4 },

  # Home & Furniture
  { parent_slug: "home", name_en: "Furniture",             name_ps: "فرنیچر",              name_fa: "مبلمان",               slug: "furniture",  icon: "🛋️", position: 1 },
  { parent_slug: "home", name_en: "Kitchen & Appliances",  name_ps: "آشپزخانه او وسایل",  name_fa: "آشپزخانه و وسایل",    slug: "kitchen",    icon: "🍳", position: 2 },
  { parent_slug: "home", name_en: "Bedding & Curtains",    name_ps: "بستر او پردې",        name_fa: "رختخواب و پرده",       slug: "bedding",    icon: "🛏️", position: 3 },
  { parent_slug: "home", name_en: "Garden & Tools",        name_ps: "باغ او وسایل",        name_fa: "باغ و ابزار",          slug: "garden",     icon: "🌿", position: 4 },

  # Books & Education
  { parent_slug: "books", name_en: "Books",           name_ps: "کتابونه",      name_fa: "کتاب‌ها",         slug: "books-general",   icon: "📖", position: 1 },
  { parent_slug: "books", name_en: "School Supplies", name_ps: "مکتب وسایل",  name_fa: "لوازم تحصیلی",   slug: "school-supplies", icon: "✏️", position: 2 },

  # Food & Agriculture
  { parent_slug: "food", name_en: "Food Products",       name_ps: "خوراکي توکي", name_fa: "محصولات غذایی", slug: "food-products", icon: "🥗", position: 1 },
  { parent_slug: "food", name_en: "Agriculture & Farming", name_ps: "کرنه",      name_fa: "کشاورزی",        slug: "agriculture",   icon: "🌾", position: 2 },
  { parent_slug: "food", name_en: "Animals & Livestock", name_ps: "حیوانات",    name_fa: "حیوانات",        slug: "livestock",     icon: "🐄", position: 3 },

  # Tools & Equipment
  { parent_slug: "tools", name_en: "Hand Tools",          name_ps: "لاسي وسایل",       name_fa: "ابزار دستی",       slug: "hand-tools",   icon: "🔨", position: 1 },
  { parent_slug: "tools", name_en: "Power Tools",         name_ps: "بریښنایي وسایل",   name_fa: "ابزار برقی",       slug: "power-tools",  icon: "🔌", position: 2 },
  { parent_slug: "tools", name_en: "Industrial Equipment", name_ps: "صنعتي تجهیزات",   name_fa: "تجهیزات صنعتی",   slug: "industrial",   icon: "🏭", position: 3 },

  # Sports & Outdoors
  { parent_slug: "sports", name_en: "Fitness Equipment", name_ps: "د فټنس وسایل", name_fa: "تجهیزات ورزشی",     slug: "fitness",       icon: "🏋️", position: 1 },
  { parent_slug: "sports", name_en: "Cycling",           name_ps: "سایکل سواري",   name_fa: "دوچرخه‌سواری",      slug: "cycling",       icon: "🚴", position: 2 },
  { parent_slug: "sports", name_en: "Outdoor Sports",    name_ps: "بهرنی سپورت",   name_fa: "ورزش فضای باز",     slug: "outdoor-sports", icon: "🏕️", position: 3 },
  { parent_slug: "sports", name_en: "Team Sports",       name_ps: "ټیمي سپورت",    name_fa: "ورزش تیمی",         slug: "team-sports",   icon: "⚽", position: 4 },

  # Beauty & Health
  { parent_slug: "beauty", name_en: "Skincare",        name_ps: "د مخ پاملرنه",         name_fa: "مراقبت پوست",       slug: "skincare",  icon: "🧴", position: 1 },
  { parent_slug: "beauty", name_en: "Haircare",        name_ps: "د وریځو پاملرنه",      name_fa: "مراقبت مو",         slug: "haircare",  icon: "💇", position: 2 },
  { parent_slug: "beauty", name_en: "Fragrances",      name_ps: "عطرونه",                name_fa: "عطریات",            slug: "fragrances", icon: "🌸", position: 3 },
  { parent_slug: "beauty", name_en: "Health & Medical", name_ps: "روغتیا",              name_fa: "بهداشت و سلامت",   slug: "health",    icon: "💊", position: 4 },

  # Bags & Accessories
  { parent_slug: "bags", name_en: "Bags & Purses", name_ps: "بیگونه",    name_fa: "کیف و کوله",  slug: "bags-purses", icon: "👜", position: 1 },
  { parent_slug: "bags", name_en: "Watches",       name_ps: "ساعتونه",   name_fa: "ساعت",        slug: "watches",     icon: "⌚", position: 2 },
  { parent_slug: "bags", name_en: "Jewelry",       name_ps: "زیورات",    name_fa: "جواهرات",     slug: "jewelry",     icon: "💍", position: 3 },

  # Kids & Toys
  { parent_slug: "kids", name_en: "Toys & Games", name_ps: "لوبوونه",        name_fa: "اسباب‌بازی",   slug: "toys",  icon: "🧸", position: 1 },
  { parent_slug: "kids", name_en: "Baby Items",   name_ps: "د ماشوم وسایل", name_fa: "لوازم نوزاد",  slug: "baby",  icon: "🍼", position: 2 }
].freeze

SUBCATEGORIES.each do |attrs|
  parent = Category.find_by!(slug: attrs[:parent_slug])
  subcat_attrs = attrs.except(:parent_slug).merge(parent_id: parent.id)
  cat = Category.find_or_initialize_by(slug: subcat_attrs[:slug])
  cat.assign_attributes(subcat_attrs)
  cat.active = true unless cat.persisted?
  cat.save!
end

# Handle old top-level "animals" category — deactivate it (listings stay on it, new ones use "livestock")
if animals_top_level
  # If it has no listings, destroy it; otherwise deactivate it so it doesn't appear in the hierarchy
  if animals_top_level.listings.empty?
    animals_top_level.destroy!
    puts "  Removed old top-level 'animals' category (no listings)"
  else
    animals_top_level.update!(active: false)
    puts "  Deactivated old top-level 'animals' category (had listings — manually re-assign)"
  end
end

puts "  categories: #{Category.count} (#{Category.top_level.count} top-level, #{Category.where.not(parent_id: nil).count} subcategories)"

# =============================================================================
# Development-only deep data
# =============================================================================
# Demo data (20 users + 50+ listings) normally seeds only in development. Set
# SEED_DEMO=true to opt in elsewhere — e.g. to populate a staging marketplace so
# the web/mobile clients show real content.
unless Rails.env.development? || ENV["SEED_DEMO"] == "true"
  puts "Non-development env — skipping deep seed data (set SEED_DEMO=true to include it)."
  return
end

puts "=== Seeding Users (20) ==="

def make_user(email:, firstname:, lastname:, city:, province:, lang:, password: "password123")
  user = User.find_or_initialize_by(email: email)
  unless user.persisted?
    user.assign_attributes(
      firstname: firstname,
      lastname:  lastname,
      password:  password,
      password_confirmation: password,
      city:       city,
      province:   province,
      preferred_language: lang,
      phone: "+93#{rand(700_000_000..799_999_999)}",
      bio:   "#{firstname} is a trusted member from #{city}.",
      uid:   email,
      provider: "email"
    )
    # Auto-confirm only when Devise :confirmable is enabled (it isn't currently),
    # so the seed works regardless of the User model's devise modules.
    user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
    user.save!
  end
  user
end

users = [
  make_user(email: "ahmad@hatiwal.com",   firstname: "Ahmad",    lastname: "Safi",      city: "Kabul",          province: "Kabul",      lang: "ps"),
  make_user(email: "omar@hatiwal.com",    firstname: "Omar",     lastname: "Noori",     city: "Kandahar",       province: "Kandahar",   lang: "ps"),
  make_user(email: "fatima@hatiwal.com",  firstname: "Fatima",   lastname: "Rahimi",    city: "Herat",          province: "Herat",      lang: "fa"),
  make_user(email: "khalid@hatiwal.com",  firstname: "Khalid",   lastname: "Wardak",    city: "Kabul",          province: "Kabul",      lang: "en"),
  make_user(email: "maryam@hatiwal.com",  firstname: "Maryam",   lastname: "Ahmadi",    city: "Mazar-i-Sharif", province: "Balkh",      lang: "fa"),
  make_user(email: "dawud@hatiwal.com",   firstname: "Dawud",    lastname: "Karimi",    city: "Jalalabad",      province: "Nangarhar",  lang: "ps"),
  make_user(email: "zainab@hatiwal.com",  firstname: "Zainab",   lastname: "Yousafi",   city: "Kabul",          province: "Kabul",      lang: "fa"),
  make_user(email: "hamid@hatiwal.com",   firstname: "Hamid",    lastname: "Sultani",   city: "Kunduz",         province: "Kunduz",     lang: "ps"),
  make_user(email: "roya@hatiwal.com",    firstname: "Roya",     lastname: "Nazari",    city: "Herat",          province: "Herat",      lang: "fa"),
  make_user(email: "bilal@hatiwal.com",   firstname: "Bilal",    lastname: "Mohammadi", city: "Ghazni",         province: "Ghazni",     lang: "ps"),
  make_user(email: "sara@hatiwal.com",    firstname: "Sara",     lastname: "Esmaili",   city: "Kabul",          province: "Kabul",      lang: "fa"),
  make_user(email: "yusuf@hatiwal.com",   firstname: "Yusuf",    lastname: "Haidari",   city: "Mazar-i-Sharif", province: "Balkh",      lang: "ps"),
  make_user(email: "nadia@hatiwal.com",   firstname: "Nadia",    lastname: "Barakzai",  city: "Kandahar",       province: "Kandahar",   lang: "ps"),
  make_user(email: "tariq@hatiwal.com",   firstname: "Tariq",    lastname: "Osmani",    city: "Jalalabad",      province: "Nangarhar",  lang: "en"),
  make_user(email: "laila@hatiwal.com",   firstname: "Laila",    lastname: "Ghafari",   city: "Herat",          province: "Herat",      lang: "fa"),
  make_user(email: "ismail@hatiwal.com",  firstname: "Ismail",   lastname: "Rahmani",   city: "Kabul",          province: "Kabul",      lang: "ps"),
  make_user(email: "habiba@hatiwal.com",  firstname: "Habiba",   lastname: "Yaqoobi",   city: "Kunduz",         province: "Kunduz",     lang: "fa"),
  make_user(email: "jawad@hatiwal.com",   firstname: "Jawad",    lastname: "Siddiqui",  city: "Kabul",          province: "Kabul",      lang: "en"),
  make_user(email: "zuhra@hatiwal.com",   firstname: "Zuhra",    lastname: "Moradi",    city: "Faizabad",       province: "Badakhshan", lang: "fa"),
  make_user(email: "demo@hatiwal.com",    firstname: "Demo",     lastname: "User",      city: "Kabul",          province: "Kabul",      lang: "en")
]

puts "  users: #{User.count}"

# =============================================================================
puts "=== Seeding Listings (50+) ==="
# =============================================================================

require "open-uri"

# Attaches real, item-appropriate photos to a listing via Active Storage.
#
# Photos come from loremflickr.com — a free, keyword-matched photo service that
# needs no API key (so it works locally and on the demo server). The `lock`
# query param makes each fetch deterministic: the same (listing, index) always
# returns the same photo, so re-running the seed never churns images.
#
# Idempotent: skips listings that already have photos. Network failures are
# non-fatal — a listing simply keeps whatever it had (or stays photo-less) and
# the seed continues, so a flaky connection never aborts the whole run.
def attach_seed_photos!(listing, query, count: 3)
  return if listing.images.attached?

  keyword = query.to_s.strip.downcase.gsub(/[^a-z0-9]+/, ",").gsub(/,+/, ",").gsub(/^,|,$/, "")
  keyword = "marketplace" if keyword.blank?

  attached = 0
  count.times do |i|
    lock = (listing.id * 10) + i # deterministic + unique per photo
    url  = "https://loremflickr.com/800/600/#{keyword}?lock=#{lock}"
    begin
      io = URI.parse(url).open(open_timeout: 10, read_timeout: 20)
      listing.images.attach(io: io, filename: "listing-#{listing.id}-#{i}.jpg", content_type: "image/jpeg")
      attached += 1
    rescue StandardError => e
      warn "  ! photo fetch failed for ##{listing.id} '#{keyword}': #{e.class} #{e.message}"
    end
  end
  print attached.positive? ? "📷" : "·"
end

cat = Category.all.index_by(&:slug)

listing_data = [
  # Electronics
  { title: "Samsung Galaxy S24 Ultra", description: "Bought 4 months ago, fully working, minor scratch on back. Original box and charger included. 256GB storage, 12GB RAM. Selling because upgrading.", price: 62_000, category: cat["electronics"], status: :active, location: "Kabul, Shahr-e-Naw", user_idx: 0, photo: "samsung,galaxy,smartphone" },
  { title: "iPhone 13 128GB", description: "Used 1 year. Battery health 89%. No cracks. FaceID works perfectly. Selling because upgrading to 15.", price: 55_000, category: cat["electronics"], status: :active, location: "Herat, City Center", user_idx: 2, photo: "iphone,smartphone" },
  { title: "Lenovo ThinkPad Laptop Core i5", description: "11th Gen Core i5, 8GB RAM, 256GB SSD. Excellent for office and development. Charger included.", price: 38_000, category: cat["electronics"], status: :active, location: "Kabul, Wazir Akbar Khan", user_idx: 3, photo: "laptop,thinkpad" },
  { title: "Sony 55 inch 4K Smart TV", description: "2022 model. Works perfectly. Selling because bought a bigger screen. Original remote and stand included.", price: 48_000, category: cat["electronics"], status: :active, location: "Mazar-i-Sharif, Downtown", user_idx: 4, photo: "television,tv" },
  { title: "Canon EOS 200D DSLR Camera", description: "18-55mm kit lens included. 300 shutter count only. Great for beginners. Camera bag and extra battery included.", price: 35_000, category: cat["electronics"], status: :reserved, location: "Kabul, Macroyan", user_idx: 6, photo: "dslr,camera" },
  { title: "JBL Xtreme 3 Bluetooth Speaker", description: "Loud sound, 15-hour battery, waterproof. Used only 5 times. Like new.", price: 9_500, category: cat["electronics"], status: :active, location: "Jalalabad", user_idx: 5, photo: "bluetooth,speaker" },
  { title: "Apple MacBook Air M1", description: "8GB RAM, 256GB SSD. Very fast and silent. All-day battery. Small scratch on lid. Original charger.", price: 72_000, category: cat["electronics"], status: :active, location: "Kabul, Qala-e-Fatullah", user_idx: 7, photo: "macbook,laptop" },
  { title: "Xiaomi Redmi Note 12 128GB", description: "6GB RAM. 50MP camera. Like new, all accessories and box included.", price: 14_500, category: cat["electronics"], status: :draft, location: "Kandahar City", user_idx: 1, photo: "smartphone,phone" },
  { title: "PlayStation 5 Disc Edition + 2 Controllers", description: "Comes with 2 games. Very good condition. Selling urgently due to travel.", price: 55_000, category: cat["electronics"], status: :active, location: "Kabul, Karte Parwan", user_idx: 8, photo: "playstation,console" },
  { title: "Huawei MateBook D15 Laptop", description: "Core i5, 8GB RAM, 512GB SSD. Slim and light. Windows 11 activated. 1 year old.", price: 32_000, category: cat["electronics"], status: :active, location: "Herat", user_idx: 9, photo: "laptop,computer" },
  { title: "Samsung Galaxy Tab A8", description: "32GB, 4GB RAM. Wi-Fi only. 10.5 inch display. Great for reading, videos, kids. Good condition.", price: 16_000, category: cat["electronics"], status: :active, location: "Kabul, Karte 3", user_idx: 15, photo: "tablet" },
  { title: "Wireless Earbuds — Samsung Galaxy Buds2", description: "Active noise cancellation. Used 3 months. Original box and case. All tips included.", price: 7_800, category: cat["electronics"], status: :active, location: "Kabul", user_idx: 17, photo: "earbuds,headphones" },

  # Clothes
  { title: "Men Traditional Perahan Tunban Set XL", description: "Brand new, size XL. Soft cotton. Blue color. Never worn. Ideal for weddings and celebrations.", price: 2_500, category: cat["clothes"], status: :active, location: "Kabul, Mandawi Bazaar", user_idx: 10, photo: "mens,clothing" },
  { title: "Women Embroidered Dress from Herat", description: "Handmade embroidery. Size M. Worn once at a wedding. Beautiful red and gold design.", price: 4_000, category: cat["clothes"], status: :active, location: "Herat", user_idx: 2, photo: "embroidered,dress" },
  { title: "Nike Air Max Sneakers Size 42", description: "Authentic Nike. Worn 3 times. Excellent condition. Original box.", price: 7_200, category: cat["clothes"], status: :active, location: "Kabul", user_idx: 3, photo: "sneakers,shoes" },
  { title: "Thick Winter Down Jacket XL Black", description: "Kept very clean. Perfect for Kabul winters. Size XL.", price: 3_800, category: cat["clothes"], status: :active, location: "Kabul, Kote Sangi", user_idx: 11, photo: "winter,jacket" },
  { title: "Wedding Dress White Size S", description: "Worn once. Dry-cleaned. Beautiful crystal design. With veil and accessories. Size S/M.", price: 12_000, category: cat["clothes"], status: :sold, location: "Mazar-i-Sharif", user_idx: 4, photo: "wedding,dress" },
  { title: "Men Suit Navy Blue Size L", description: "Worn twice. Very good condition. Comes with tie. Suitable for formal occasions.", price: 8_500, category: cat["clothes"], status: :active, location: "Kabul, Shar-e-Naw", user_idx: 0, photo: "suit,men" },

  # Vehicles
  { title: "Toyota Corolla 2015 Low Mileage", description: "Single owner. 85,000 km. Full service history. Clean interior. AC works. No accidents.", price: 1_250_000, category: cat["vehicles"], status: :active, location: "Kabul, Sarak-e-Darulaman", user_idx: 1, photo: "toyota,corolla,car" },
  { title: "Honda CG 125 Motorbike 2021", description: "Red color. Good engine. No rust. Second owner. Registration done. Comes with extra tyres.", price: 85_000, category: cat["vehicles"], status: :active, location: "Kandahar", user_idx: 1, photo: "motorcycle,motorbike" },
  { title: "Toyota Land Cruiser 2008 4WD Diesel", description: "Excellent off-road. New tyres. AC working. 180,000 km. All documents available.", price: 2_800_000, category: cat["vehicles"], status: :active, location: "Jalalabad", user_idx: 5, photo: "landcruiser,suv,car" },
  { title: "Suzuki Mehran 2019 White", description: "One owner. City use only. Low mileage. All documents. Selling due to travel.", price: 420_000, category: cat["vehicles"], status: :reserved, location: "Kabul", user_idx: 15, photo: "car,white" },
  { title: "Electric Bicycle 48V Foldable", description: "25km range per charge. Great for city commute. 6 months old. Charger included.", price: 32_000, category: cat["vehicles"], status: :active, location: "Herat", user_idx: 9, photo: "electric,bicycle" },

  # Home & Furniture
  { title: "8-Seat Wooden Dining Table Set", description: "Solid wood. 8 matching chairs. Good condition. Light scratch on one chair. Must collect in Kabul.", price: 28_000, category: cat["home"], status: :active, location: "Kabul, Macroyan 3", user_idx: 6, photo: "dining,table" },
  { title: "King Size Bed Frame and Mattress", description: "Imported wood frame. Spring mattress. Used 2 years. Very comfortable. No stains.", price: 22_000, category: cat["home"], status: :active, location: "Mazar-i-Sharif", user_idx: 12, photo: "bed,bedroom" },
  { title: "Samsung 350L Two-Door Fridge", description: "Works perfectly. 3 years old. Small dent on side (cosmetic). Full size, great for families.", price: 18_000, category: cat["home"], status: :active, location: "Kabul, Qala-e-Zaman Khan", user_idx: 0, photo: "refrigerator,fridge" },
  { title: "Gas Cooking Range 4 Burners", description: "Excellent condition. 1 year old. All burners work. Delivery within Kabul included.", price: 8_500, category: cat["home"], status: :active, location: "Kabul", user_idx: 16, photo: "stove,cooking" },
  { title: "Persian Hand-Woven Carpet 3x5 Meter", description: "Authentic Afghan carpet from Kunduz. Rich colors. No tears or fading. Ideal for living room.", price: 45_000, category: cat["home"], status: :active, location: "Kunduz", user_idx: 7, photo: "carpet,rug" },
  { title: "LG Fully Automatic Washing Machine 7kg", description: "Works great. 2 years old. All cycles functional. Selling due to moving.", price: 12_000, category: cat["home"], status: :active, location: "Herat", user_idx: 14, photo: "washing,machine" },
  { title: "L-Shaped Sofa Set 6 Seats", description: "Light brown fabric. Very comfortable. 18 months old. No damage.", price: 35_000, category: cat["home"], status: :draft, location: "Kabul, Karte 4", user_idx: 3, photo: "sofa,couch" },

  # Books
  { title: "Engineering Textbooks Collection 10 Books", description: "Calculus, Physics, Circuits, Algorithms and more. Used one semester. All in English.", price: 3_500, category: cat["books"], status: :active, location: "Kabul, Polytechnic", user_idx: 13, photo: "textbooks,books" },
  { title: "Pashto Learning Books Beginner to Advanced", description: "5-book series. Excellent for language learners. Some notes inside.", price: 2_200, category: cat["books"], status: :active, location: "Kabul", user_idx: 0, photo: "books" },
  { title: "Medical Anatomy Atlas Grays 42nd Edition", description: "Like new. A few pages highlighted. Essential for medical students.", price: 4_800, category: cat["books"], status: :active, location: "Kabul, Aliabad Medical Area", user_idx: 8, photo: "medical,book" },
  { title: "Quran with Dari Translation Large Print", description: "Hardcover. New condition. Bought as gift, already have one.", price: 800, category: cat["books"], status: :active, location: "Mazar-i-Sharif", user_idx: 4, photo: "quran,book" },

  # Food
  { title: "Fresh Pomegranates from Kandahar 50kg Bulk", description: "Freshly harvested. Sweet Kandahari variety. Bulk orders available. Delivery to Kabul possible.", price: 4_500, category: cat["food"], status: :active, location: "Kandahar", user_idx: 1, photo: "pomegranate,fruit" },
  { title: "Organic Saffron from Herat 500g Premium", description: "Certified organic. Sealed packaging. Premium grade. Great for cooking and export.", price: 22_000, category: cat["food"], status: :active, location: "Herat", user_idx: 2, photo: "saffron,spice" },
  { title: "Wild Mountain Honey from Nuristan 1kg Jars", description: "Pure wild honey. No additives. Minimum order 3 jars. Very limited stock.", price: 1_200, category: cat["food"], status: :active, location: "Jalalabad", user_idx: 5, photo: "honey,jar" },

  # Tools
  { title: "Makita Drill Set with Bits and 2 Batteries", description: "Makita DF487D. Used twice. All bits included. Like new condition.", price: 8_200, category: cat["tools"], status: :active, location: "Kabul, Industrial Area", user_idx: 15, photo: "drill,tools" },
  { title: "MMA Welding Machine 200A", description: "Good condition. Cables and welding mask included. Works on 220V generator.", price: 12_000, category: cat["tools"], status: :active, location: "Kandahar", user_idx: 1, photo: "welding,machine" },
  { title: "Carpenter Tool Box 30 Pieces", description: "Hammers, saws, chisels, squares. Organized metal box. Good quality tools.", price: 5_500, category: cat["tools"], status: :active, location: "Kabul", user_idx: 7, photo: "tools,toolbox" },

  # Property
  { title: "2-Bedroom Apartment for Rent Kabul", description: "Modern flat, 90 sqm. 2nd floor. Backup power. Security guard. Near Kabul University.", price: 18_000, category: cat["property"], status: :active, location: "Kabul, Karte Char", user_idx: 11, photo: "apartment,interior" },
  { title: "Shop Space for Rent in Herat Bazaar", description: "15 sqm. Ground floor. Busy street. Electricity available. Suit for clothing or electronics.", price: 12_000, category: cat["property"], status: :active, location: "Herat, Main Bazaar", user_idx: 14, photo: "shop,storefront" },

  # Services
  { title: "Professional Tailoring Men and Women", description: "Traditional and modern clothes. 20 years experience. Work done in 2-3 days. Bring your fabric.", price: 500, category: cat["services"], status: :active, location: "Herat, Tailors Street", user_idx: 2, photo: "tailor,sewing" },
  { title: "Home Electrician All Kabul Areas", description: "Wiring, solar panels, inverter installation. 10 years experience. Available daily.", price: 800, category: cat["services"], status: :active, location: "Kabul", user_idx: 0, photo: "electrician,wiring" },

  # Other
  { title: "Chicco Baby Stroller Barely Used", description: "Folds easily. Navy blue. Used 3 months. All parts working. Rain cover included.", price: 5_500, category: cat["other"], status: :active, location: "Kabul, Wazir Akbar Khan", user_idx: 6, photo: "stroller,baby" },
  { title: "Motorized Treadmill Foldable", description: "Speed up to 12 km/h. Works well. 2 years old. Heavy item. Selling due to moving.", price: 16_000, category: cat["other"], status: :active, location: "Kabul, Karte Seh", user_idx: 18, photo: "treadmill,gym" },
  { title: "Children Bicycle Age 5 to 8", description: "Red color. Training wheels attached. Helmet included. No rust.", price: 2_800, category: cat["other"], status: :active, location: "Mazar-i-Sharif", user_idx: 4, photo: "kids,bicycle" },

  # ── Pashto listings (title + description in Pashto) — for RTL testing ────────
  { title: "د سامسنګ ګلکسي A54 نوی موبایل", description: "بشپړ نوی، د بکس او چارجر سره. ۱۲۸ ګیګابایټه حافظه، ۸ ګیګابایټه رام. رنګ تور. د ضمانت سره خرڅلاو. په کابل کې ملاقات کیدای شي.", price: 24_000, category: cat["electronics"], status: :active, location: "کابل، شهر نو", user_idx: 0, photo: "samsung,smartphone" },
  { title: "د لرګي د خوب کوټې الماري", description: "درې دروازې لرګینه الماري، ښه حالت لري، دوه کاله زوړ. د کډې کولو له امله خرڅلاو. په کابل کې پورته کول.", price: 15_000, category: cat["home"], status: :active, location: "کابل، کارته نو", user_idx: 7, photo: "wardrobe,furniture" },
  { title: "افغاني لاسي جوړ قالین ۳x۴ متره", description: "اصلي افغاني قالین، ښکلي رنګونه لري، هیڅ زیان یا رنګ تلل نلري. د میلمستون او خوب کوټې لپاره مناسب دی.", price: 38_000, category: cat["home"], status: :active, location: "کندهار ښار", user_idx: 1, photo: "carpet,rug" },

  # ── Dari listings (title + description in Dari) — for RTL testing ────────────
  { title: "گوشی شیائومی ردمی نوت ۱۳ نو", description: "کاملاً نو، همراه با جعبه و شارژر اصلی. ۲۵۶ گیگابایت حافظه، رنگ آبی. قیمت قابل معامله است. محل ملاقات مرکز شهر هرات.", price: 22_000, category: cat["electronics"], status: :active, location: "هرات، مرکز شهر", user_idx: 2, photo: "xiaomi,smartphone" },
  { title: "یخچال ال جی دو درب کم کارکرد", description: "به خوبی کار می‌کند، سه سال استفاده شده و هیچ خرابی ندارد. به دلیل نقل مکان به فروش می‌رسد. تحویل در مزار شریف.", price: 17_000, category: cat["home"], status: :active, location: "مزار شریف", user_idx: 4, photo: "refrigerator,fridge" },
  { title: "دوچرخه کوهی حرفه‌ای ۲۹ اینچ", description: "دوچرخه کوهی با دنده‌های شیمانو، سبک و مقاوم. کمتر از یک سال استفاده شده. مناسب برای شهر و مسیرهای کوهی.", price: 14_000, category: cat["vehicles"], status: :active, location: "هرات", user_idx: 8, photo: "mountain,bicycle" }
]

listing_data.each do |d|
  seller = users[d[:user_idx]]
  next if d[:category].nil?

  # find_or_create so a re-run backfills photos onto listings seeded before
  # photo support existed, instead of skipping them entirely.
  listing = Listing.find_by(user: seller, title: d[:title])
  listing ||= Listing.create!(
    user:        seller,
    category:    d[:category],
    title:       d[:title],
    description: d[:description],
    price:       d[:price],
    currency:    "AFN",
    status:      d[:status],
    location:    d[:location],
    views_count: rand(3..420)
  )

  attach_seed_photos!(listing, d[:photo])
end
puts "" # newline after the per-listing photo progress dots

puts "  listings: #{Listing.count} (#{Listing.active.count} active, #{Listing.draft.count} draft, #{Listing.reserved.count} reserved, #{Listing.sold.count} sold)"

# =============================================================================
puts "=== Seeding Saved Listings ==="
# =============================================================================

active_listings = Listing.active.to_a

saved_pairs = [
  [ users[0],  4 ],
  [ users[2],  5 ],
  [ users[3],  3 ],
  [ users[5],  3 ],
  [ users[8],  4 ],
  [ users[13], 6 ],
  [ users[19], 8 ]
]

saved_pairs.each do |user, count|
  active_listings.sample(count).each do |listing|
    next if listing.user == user
    next if SavedListing.exists?(user: user, listing: listing)

    SavedListing.create!(user: user, listing: listing)
  rescue ActiveRecord::RecordNotUnique
    next
  end
end

puts "  saved_listings: #{SavedListing.count}"

# =============================================================================
puts "=== Seeding Conversations & Messages ==="
# =============================================================================

# Each thread is an array of [message_body, kind]
CHAT_THREADS = {
  pashto_electronics: [
    [ "السلام علیکم، آیا دا توکی لا شتون دی؟", :text ],
    [ "وعلیکم السلام، هو لا شتون دی 😊", :text ],
    [ "قیمت یی کمول کیدای شی؟", :text ],
    [ "ورور، قیمت ثابت دی، خو که نقده راشی نو ۵۰۰ AFN کمولای شم", :text ],
    [ "باشه، کله ملاقات کولای شو؟", :text ],
    [ "سبا سهار ۱۰ بجه مناسب دی؟", :text ],
    [ "د شهرنو مارکیټ سره نږدې ملاقات کوو؟", :text ],
    [ "هو، هغه ځای مناسب دی، ډیر خلک وي", :text ],
    [ "باشه موافق یم، سبا ګورو 🙏", :text ],
    [ "ښه، زه به ستاسو انتظار وکم", :text ]
  ],
  pashto_vehicle: [
    [ "سلام، د موټر حالت سم دی؟", :text ],
    [ "هو ورور، خپل سترګو سره یی وګوره، مشکل نشته", :text ],
    [ "ایا انجن بدل شوی؟", :text ],
    [ "نه، اصلي انجن دی. ټول سروس ریکارد موجود دی", :text ],
    [ "قیمت لږ ښکته کیدای شی؟ زه نقده راوړم", :text ],
    [ "که ۱،۲۰۰،۰۰۰ راکوې نو معامله ده 🤝", :text ],
    [ "باشه موافق یم. سبا کله ملاقات کولای شو؟", :text ],
    [ "بعد له چاشت ۳ بجه کابل، دارالامان سړک", :text ],
    [ "سم ده، زه به هلته وم ان شاء الله 🙏", :text ],
    [ "ښه، زه به موټر پاک کوم چې وګورئ", :text ]
  ],
  dari_general: [
    [ "سلام، آیا این کالا هنوز موجود است؟", :text ],
    [ "بلی، موجود است 😊", :text ],
    [ "قیمت ثابت است یا می‌توانیم صحبت کنیم؟", :text ],
    [ "اگر نقد بیاید ۱۰٪ تخفیف می‌دهم", :text ],
    [ "بسیار عالی! کجا می‌توانیم ملاقات کنیم؟", :text ],
    [ "نزدیک میدان هوایی کابل، مکان امن و شلوغ", :text ],
    [ "چه وقت برای شما مناسب است؟", :text ],
    [ "فردا بعد از ظهر ساعت ۴ خوب است؟", :text ],
    [ "بسیار خوب، فردا می‌بینیم 🙏", :text ],
    [ "اگر نیاز به تست دارید با خود بیاورید", :text ],
    [ "ممنون، حتماً می‌آیم", :text ],
    [ "منتظرتان هستم", :text ]
  ],
  dari_meetup: [
    [ "سلام برادر، کالا هنوز هست؟", :text ],
    [ "بلی هست، بفرمایید ببینید", :text ],
    [ "عکس بیشتر دارید؟", :text ],
    [ "بلی عکس‌های بیشتر می‌فرستم", :text ],
    [ "خیلی خوب به نظر می‌رسد. قیمت آخرتان چقدر است؟", :text ],
    [ "همان قیمت نوشته شده، قابل مذاکره است", :text ],
    [ "اگر امروز بیایم می‌توانیم معامله کنیم؟", :text ],
    [ "بلی، هر وقت بیایید آماده‌ام", :text ],
    [ "یک ساعت دیگر می‌آیم", :text ],
    [ "منتظرم، آدرس دقیق می‌فرستم", :text ],
    [ "ممنون، در راهم", :text ],
    [ "رسیدید؟", :text ],
    [ "بلی جلوی در هستم", :text ],
    [ "معامله خوب بود، ممنون 🙏", :text ],
    [ "خواهش می‌کنم، موفق باشید 😊", :text ]
  ],
  english_short: [
    [ "Hello, is this still available?", :text ],
    [ "Yes, available! You can come see it anytime 😊", :text ],
    [ "Can we meet today?", :text ],
    [ "Sure, after 3pm works for me", :text ],
    [ "What location is best?", :text ],
    [ "Shahr-e-Naw park near the fountain — safe and busy", :text ],
    [ "Perfect, I will be there at 4pm", :text ],
    [ "See you then. I will be wearing a blue jacket 👍", :text ],
    [ "Deal done, thank you!", :text ],
    [ "Thank you too, pleasure doing business 🙏", :text ]
  ],
  english_negotiation: [
    [ "Hi, I am interested in this item. Is it still for sale?", :text ],
    [ "Yes it is! Feel free to come check it out", :text ],
    [ "What is the lowest price you can do?", :text ],
    [ "I can do a small discount if you pay cash today", :text ],
    [ "How about 10% less?", :text ],
    [ "That works for me. When can we meet?", :text ],
    [ "Tomorrow morning between 9 and 12 is best for me", :text ],
    [ "Works for me. Where should we meet?", :text ],
    [ "Near Kabul University gate, easy to find", :text ],
    [ "Great, see you tomorrow at 10am", :text ],
    [ "Perfect. I will bring the cash 💰", :text ],
    [ "Excellent! See you then 🙏", :text ]
  ]
}.freeze

def seed_conversation(buyer, listing, thread_key)
  return if listing.nil?
  return if listing.user == buyer
  return if Conversation.exists?(listing: listing, buyer: buyer)

  conversation = Conversation.create!(
    listing: listing,
    buyer:   buyer,
    seller:  listing.user
  )

  thread = CHAT_THREADS[thread_key]
  base_time = rand(2..90).days.ago

  thread.each_with_index do |(body, kind), idx|
    sender   = idx.even? ? buyer : listing.user
    msg_time = base_time + (idx * rand(3..180)).minutes
    read     = idx < thread.length - 2

    msg = Message.new(
      conversation: conversation,
      user:         sender,
      body:         body,
      kind:         kind,
      read_at:      read ? msg_time + rand(1..60).minutes : nil
    )
    msg.created_at  = msg_time
    msg.updated_at  = msg_time
    msg.save!
  end

  conversation
rescue ActiveRecord::RecordInvalid
  nil
end

# Seeded conversations — varied languages and categories
[
  [ users[0],  "Samsung Galaxy S24 Ultra",           :pashto_electronics ],
  [ users[3],  "iPhone 13 128GB",                    :english_negotiation ],
  [ users[13], "Toyota Corolla 2015",                :english_negotiation ],
  [ users[19], "Apple MacBook Air M1",               :english_short ],
  [ users[5],  "PlayStation 5 Disc Edition",         :pashto_electronics ],
  [ users[8],  "Persian Hand-Woven Carpet",          :dari_general ],
  [ users[2],  "MMA Welding Machine",                :dari_general ],
  [ users[6],  "Toyota Land Cruiser",                :pashto_vehicle ],
  [ users[10], "King Size Bed Frame",                :dari_meetup ],
  [ users[14], "Canon EOS 200D DSLR",               :english_short ],
  [ users[7],  "Honda CG 125 Motorbike",             :pashto_vehicle ],
  [ users[18], "8-Seat Wooden Dining Table",         :dari_general ],
  [ users[9],  "JBL Xtreme 3 Bluetooth",             :pashto_electronics ],
  [ users[15], "Organic Saffron from Herat",         :dari_meetup ],
  [ users[11], "Fresh Pomegranates from Kandahar",   :pashto_electronics ],
  [ users[17], "LG Fully Automatic Washing Machine", :dari_general ],
  [ users[12], "Gas Cooking Range 4 Burners",        :dari_meetup ],
  [ users[16], "Carpenter Tool Box",                 :pashto_electronics ],
  [ users[6],  "Kuchi Shepherd Dog",                 :dari_general ],
  [ users[9],  "Chicco Baby Stroller",               :english_negotiation ],
  [ users[3],  "Motorized Treadmill",                :english_short ],
  [ users[19], "3 Dairy Cows Holstein",              :dari_general ],
  [ users[0],  "Electric Bicycle 48V",               :pashto_electronics ],
  [ users[13], "Quran with Dari Translation",        :dari_general ],
  [ users[5],  "Medical Anatomy Atlas",              :english_negotiation ]
].each do |buyer, fragment, thread|
  listing = Listing.where("title ILIKE ?", "%#{fragment}%").first
  seed_conversation(buyer, listing, thread)
end

puts "  conversations: #{Conversation.count}, messages: #{Message.count}"

# =============================================================================
puts "=== Seeding Reports ==="
# =============================================================================

report_targets = Listing.active.limit(6).to_a

[
  { reporter: users[19], target: report_targets[0], reason: :spam,             description: "This listing is posted multiple times with different prices." },
  { reporter: users[3],  target: report_targets[1], reason: :fraud,            description: "Seller asked for advance payment then stopped responding." },
  { reporter: users[13], target: report_targets[2], reason: :wrong_category,   description: "This is a service listing but posted under electronics." },
  { reporter: users[5],  target: users[1],          reason: :fraud,            description: "This user is a scammer — asked for money upfront and disappeared." },
  { reporter: users[8],  target: report_targets[3], reason: :inappropriate,    description: "Description contains offensive language." },
  { reporter: users[2],  target: report_targets[4], reason: :prohibited_item,  description: "This item is not allowed in the marketplace per community rules." }
].each do |r|
  next if r[:target].nil?
  next if Report.exists?(reporter: r[:reporter], reportable: r[:target])

  Report.create!(
    reporter:    r[:reporter],
    reportable:  r[:target],
    reason:      r[:reason],
    description: r[:description],
    status:      [ :pending, :reviewed, :dismissed ].sample
  )
rescue ActiveRecord::RecordInvalid
  next
end

puts "  reports: #{Report.count}"

# =============================================================================
puts ""
puts "======================================"
puts "  SEED COMPLETE"
puts "======================================"
puts "  Users:         #{User.count}"
puts "  Categories:    #{Category.count} (#{Category.top_level.count} top-level)"
puts "  Listings:      #{Listing.count}"
puts "    active:      #{Listing.active.count}"
puts "    draft:       #{Listing.draft.count}"
puts "    reserved:    #{Listing.reserved.count}"
puts "    sold:        #{Listing.sold.count}"
puts "  Saved:         #{SavedListing.count}"
puts "  Conversations: #{Conversation.count}"
puts "  Messages:      #{Message.count}"
puts "  Reports:       #{Report.count}"
puts ""
puts "  Accounts (password: password123)"
puts "  demo@hatiwal.com     general demo"
puts "  ahmad@hatiwal.com    Kabul buyer/seller (ps)"
puts "  omar@hatiwal.com     Kandahar seller — vehicles & electronics (ps)"
puts "  fatima@hatiwal.com   Herat seller — clothes & food (fa)"
puts "  khalid@hatiwal.com   Kabul buyer (en)"
puts "  maryam@hatiwal.com   Mazar seller — home & animals (fa)"
puts "======================================"
