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
#   seller@hatiwal.test   — seller with draft / active / reserved listings;
#                           ALSO the buyer on one thread (own listing "Mountain
#                           Bike 26-inch Steel Frame", owned by newbuyer) — the
#                           one account with both a Selling and a Buying
#                           thread, for the TASK-R517 role-filter E2E flow.
#   newbuyer@hatiwal.test — fresh account, no saved/bought history; owns the
#                           one listing seller@hatiwal.test messages about
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
    user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
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

# An EMPTY seller — owns nothing, ever. mode/seller_mode_my_listings_empty logs in as
# new_seller@hatiwal.test, switches to seller mode and asserts the "You haven't posted
# anything yet" state; the account was referenced by that flow and seeded nowhere, so the
# login could not complete and it failed with "Element not found: profile-tab" — a
# missing tab bar standing in for a missing account.
#
# It has to stay listing-less to be useful, so nothing below may give it one: buyer@ and
# newbuyer@ each own one, which is why neither could serve here.
new_seller = e2e_user(email: "new_seller@hatiwal.test", firstname: "Zainab", lastname: "Popal", city: "Mazar-i-Sharif", province: "Balkh")
puts "  new_seller@hatiwal.test — empty seller, owns #{new_seller.listings.count} listing(s) (must stay 0)"

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

def e2e_listing(user:, title:, price:, category:, status:, description:, location:, latitude: nil, longitude: nil, quantity: 1, expires_at: nil)
  # RESET the status of a fixture that already exists, rather than leaving it wherever
  # the flows left it.
  #
  # This used to be a bare `return if exists?`, and shared fixtures drifted
  # permanently as a result: flows reserve and sell them and nothing put them back. By
  # the time this was noticed three seeded :active listings were in the wrong state —
  # Lenovo ThinkPad and Traditional Kandahari Carpet stuck RESERVED, Wool Blanket stuck
  # SOLD. (Xiaomi Redmi Note 11 is also SOLD and belongs that way: it is seeded :sold
  # as the fixture for sold-listing flows. Worth stating, because a status audit that
  # does not check the seeded intent flags it as drift.)
  #
  # That is not a cosmetic drift. A sold listing leaves the browsable feed, so every
  # flow that scrolls to one of them fails with "No visible element found" for a
  # fixture that exists — a missing-fixture message for a listing that is merely in
  # the wrong state. It also made single-shot flows out of repeatable ones:
  # reviews/rate_buyer_after_sale marks the Lenovo sold as its own setup, so it could
  # only ever work once per database, and after it ran the eight flows that share that
  # listing lost their active fixture.
  #
  # Same semantics as the DISPOSABLE_LISTINGS reset further down, which solved exactly
  # this for the "QA Disposable" listings; seeded fixtures need it just as much.
  if (existing = Listing.find_by(user: user, title: title))
    if existing.status.to_sym != status
      existing.update_columns(
        status:       Listing.statuses[status],
        published_at: %i[active reserved sold].include?(status) ? 2.days.ago : nil,
        reserved_at:  status == :reserved ? 1.day.ago : nil,
        sold_at:      status == :sold ? 1.day.ago : nil
      )
      puts "  reset listing [#{status}] #{title}"
    end
    # An EXPIRY fixture has to be restored too, or it stops being expired the first time
    # a flow renews it (listings/listing_renew_flow pushes expires_at 30 days out) and
    # every later run of listings/expired_listing_badge finds an empty "Expired" tab.
    if expires_at && existing.expires_at != expires_at
      existing.update_columns(expires_at: expires_at)
      puts "  reset expiry #{title} -> #{expires_at.to_date}"
    end
    return
  end

  attrs = {
    user:        user,
    category:    category,
    title:       title,
    description: description,
    price:       price,
    currency:    "AFN",
    status:      status,
    location:    location,
    # Multi-quantity (docs/SPIKE_LISTING_QUANTITY.md). Defaults to 1, so every
    # existing fixture stays a single-item listing and the flows written against
    # them are unaffected.
    quantity:    quantity,
    views_count: rand(5..200)
  }

    # A published listing REQUIRES an exact pin: getPublishBlockers refuses to
    # publish without lat/long, so a seeded :active listing with no coordinates is
    # a state the app itself could never have produced. 51 of 53 active fixtures
    # were exactly that, which also left the listing-detail Location section (and
    # its map) with nothing to render from — browse/listing_detail failed scrolling
    # to a section that legitimately did not exist. Callers may pass their own pin;
    # drafts stay pinless on purpose, since a draft is allowed to be incomplete.
    if %i[active reserved sold].include?(status)
      attrs[:latitude]  = latitude || 34.5553
      attrs[:longitude] = longitude || 69.2075
    elsif latitude && longitude
      attrs[:latitude]  = latitude
      attrs[:longitude] = longitude
    end

  attrs[:published_at] = rand(1..30).days.ago if %i[active reserved sold].include?(status)
  attrs[:reserved_at]  = rand(1..7).days.ago   if status == :reserved
  attrs[:sold_at]      = rand(1..14).days.ago  if status == :sold
  # `expired` is not a status. Listing#expired? is `active? && expires_at.past?`
  # (listing.rb:240), so an expired fixture is an ACTIVE row with a past expires_at.
  attrs[:expires_at]   = expires_at if expires_at

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

# ── Expired fixture ─────────────────────────────────────────
# There was no expired listing at all, so My Shop's "Expired" tab counted 0 and two
# flows could not run: listings/expired_listing_badge failed with "Element not found:
# seller-listing-card" on an empty tab, and listings/listing_renew_flow had nothing to
# renew.
#
# "expired" is NOT a status — Listing#expired? is `active? && expires_at.past?`
# (listing.rb:240) — so this is an ACTIVE row with expires_at in the past. The reset in
# e2e_listing restores that date, which matters because listing_renew_flow's whole
# purpose is to push it 30 days out.
e2e_listing(
  user:        seller,
  title:       "Expired Winter Coat Size L",
  price:       1_800,
  category:    clothes,
  status:      :active,
  expires_at:  3.days.ago,
  description: "Listed a while ago and never renewed. Warm wool coat, worn twice.",
  location:    "Kabul, Karte Naw"
)

# ── Ready-to-publish draft ──────────────────────────────────
# The publish path needs a draft that CAN be published: a photo and an exact pin
# (getPublishBlockers, and the API agrees). This used to be "whichever draft has the
# lowest id", which no flow can target — listings/lifecycle_publish taps the first card
# on the Draft tab, and that is whatever a create/edit flow made most recently. It got a
# photoless QA draft, publish was refused, and the failure read as a broken Publish
# button ("Assertion is false: Publish this listing? is visible").
#
# A distinct title fixes that: flows can search for exactly this one. The pin is passed
# here because e2e_listing leaves drafts unpinned on purpose — a draft is allowed to be
# incomplete — and the photo block below adds this title to its targets.
e2e_listing(
  user:        seller,
  title:       "Ready To Publish Draft",
  price:       6_500,
  category:    electronics,
  status:      :draft,
  latitude:    34.5553,
  longitude:   69.2075,
  description: "Complete draft with a photo and a pin, so the publish path is reachable.",
  location:    "Kabul, Shar-e-Naw"
)

e2e_listing(
  user:        seller,
  title:       "Lenovo ThinkPad Laptop Core i5 8GB",
  # 32_300, not 38_000: this listing carries the seeded price-drop history below
  # (38 000 -> 32 300, ~15%), and the price has to be the POST-drop figure or the
  # fixture contradicts itself — buyers saw "AFN 38,000" next to a "↓15%" badge.
  # Kept above reserved_buyer's negotiated 32_000 so that flow still reads as a
  # discount on the asking price.
  price:       32_300,
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

# Multi-quantity (docs/SPIKE_LISTING_QUANTITY.md, Tier 1) — the reseller case
# the feature was built for: one listing, 15 identical units. Drives the "each"
# per-unit price, the stock pill, and the buyer picker's "How many did you sell?"
# field. Kept as the ONLY multi-unit fixture so every other flow keeps asserting
# the single-item majority case.
# ── SF-M11 — a multi-unit listing dedicated to the OFFER-QUANTITY flow ──────
# Its own fixture on purpose. The Phone Case above is the canonical multi-unit
# listing but it already carries a seeded conversation and an unread-state helper
# (maestro/_helpers/make_phone_case_unread.yaml), and the offer-quantity flow
# MUTATES a thread — sending an offer, accepting it, marking units sold. Sharing
# a fixture between two mutating flows is how they start failing for each other's
# reasons, which is why this seed already keeps the sell-flow listings apart.
#
# Seller-owned and `active` with NO pre-seeded conversation, so the flow can drive
# the whole round trip from a clean thread: buyer states 3 units, seller accepts,
# and mark-sold must open on 3 rather than 1.
e2e_listing(
  user:        seller,
  title:       "Wool Socks Bulk Pack - 12 Pairs",
  price:       250,
  category:    clothes,
  status:      :active,
  description: "Twelve pairs, thick wool. Happy to sell a few pairs or the whole pack.",
  location:    "Kandahar, Main Road",
  quantity:    12
)

e2e_listing(
  user:        seller,
  title:       "Phone Case Silicone Clear - Wholesale",
  price:       400,
  category:    electronics,
  status:      :active,
  description: "Bought a box of 15. Selling individually or in bulk. Fits most 6.1 inch phones.",
  location:    "Kandahar, Main Road",
  quantity:    15
)

# ── SF-QA1 (card #296) — the five SELL-FLOW fixtures ────────────────────────
# The listings only. Their ledgers (the open hold, the sold rows, the outside
# buyer, the review) are rebuilt further down in
# "=== E2E Seed: Sell-flow states ===" — same split the Phone Case above already
# uses (listing here, its conversation at "Multi-quantity conversation"), because
# a Transaction needs a Conversation which needs a Listing.
#
# Created here rather than beside that section so the photo block below can see
# them: this is a photo-first marketplace and these five are screenshotted by the
# sell-flow QA run.
#
# NOT the Phone Case, and not each other: maestro/chat/place_and_release_hold.yaml
# opens the Phone Case and asserts `composer-action-release-hold` is ABSENT
# before it places its own hold, so the one batch that must keep 0 held units is
# exactly the batch that was already there. Every fixture below owns its own
# state for the same reason.
SELL_FLOW_FIXTURE_TITLES = [
  "Winter Gloves Wholesale Box - 15 Pairs",
  "Solar Lantern Rechargeable - Batch of 6",
  "School Backpack Bulk Restock - 20 Bags",
  "Steel Thermos Flask 1L - Bulk Batch",
  "Electric Kettle 1.8L Stainless - Bulk 10"
].freeze

# 1. Open HOLD on a live batch — 15 pairs, 10 held for one buyer.
e2e_listing(
  user:        seller,
  title:       SELL_FLOW_FIXTURE_TITLES[0],
  price:       350,
  category:    clothes,
  status:      :active,
  quantity:    15,
  description: "Box of 15 pairs, wool lined. Selling by the pair or the whole box.",
  location:    "Kandahar, Main Road"
)

# 2. SOLD OUT — every unit accounted for by a sold ledger row.
e2e_listing(
  user:        seller,
  title:       SELL_FLOW_FIXTURE_TITLES[1],
  price:       1_200,
  category:    electronics,
  status:      :sold,
  quantity:    6,
  description: "Rechargeable solar lanterns, batch of six. USB charging, 8 hours per charge.",
  location:    "Kabul, Karte Naw"
)

# 3. Sold out, then quantity RAISED — live again with 5 left. The owner's own
#    bug report (SF-B6): 15 of 15 sold and edited to 20 used to stay `sold`.
e2e_listing(
  user:        seller,
  title:       SELL_FLOW_FIXTURE_TITLES[2],
  price:       600,
  category:    clothes,
  status:      :active,
  quantity:    20,
  description: "Sturdy school backpacks, two compartments. The first batch sold out and I restocked.",
  location:    "Kabul, Shar-e-Naw"
)

# 4. Partially sold to SEVERAL buyers, one of them not on Hatiwal — the Sales
#    ledger fixture (SF-B5). Nothing else seeds more than one sale per listing.
e2e_listing(
  user:        seller,
  title:       SELL_FLOW_FIXTURE_TITLES[3],
  price:       800,
  category:    home,
  status:      :active,
  quantity:    15,
  description: "One litre stainless steel flasks, keeps tea hot 12 hours. Selling from a batch of 15.",
  location:    "Kandahar, Old Bazaar"
)

# 5. A sold sale that already carries a REVIEW — void/reassign must be refused
#    (422 `sale_has_review`) while a quantity edit still goes through (SF-B4).
e2e_listing(
  user:        seller,
  title:       SELL_FLOW_FIXTURE_TITLES[4],
  price:       1_500,
  category:    home,
  status:      :active,
  quantity:    10,
  description: "1.8 litre stainless kettle, 1500W. Ten in stock, selling individually.",
  location:    "Kandahar"
)

# TASK-K729 — dedicated fixtures for the chat "reserved/sold dead end"
# recovery-notice flows, kept distinct from every other active listing above
# (each already claimed by its own mutating Maestro flow) so
# maestro/chat/reserved_sold_dead_end_notice.yaml and
# maestro/chat/reserved_for_you_notice.yaml never collide with each other or
# with reserve_after_accept.yaml / offer_send_and_accept.yaml / mark_sold_with_buyer.yaml.

# Legacy (buyer-less) reserve/sold path — the recovery notice's GENERIC copy
# (no committed buyer identified via the buyer picker).
e2e_listing(
  user:        seller,
  title:       "Wool Blanket Handmade King Size",
  price:       4_200,
  category:    home,
  status:      :active,
  description: "Thick handmade wool blanket. King size. Warm for winter nights.",
  location:    "Kandahar, Old Bazaar"
)

# Buyer-identified reserve/sold path (via the in-thread offer -> accept ->
# BuyerPickerSheet confirm) — the recovery notice's VIEWER-SCOPED copy
# ("Reserved for you" / "You bought this item") for the buyer who actually
# won the deal.
e2e_listing(
  user:        seller,
  title:       "Bajaj CT100 Motorbike 2021",
  price:       62_000,
  category:    vehicles,
  status:      :active,
  description: "Fuel efficient commuter bike. Well maintained, all papers clear.",
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
puts "=== E2E Seed: Listing photos ==="
# =============================================================================
# The e2e fixtures had NO photos at all — 0 of the seller's listings, while the
# main dev seed gives 55 of 67 listings three each. Consequences:
#
#   * every gallery flow was unsatisfiable (nothing to swipe through)
#   * every QA screenshot showed "No photo", so the photo-first design this app
#     is built around could not be reviewed from a single e2e run
#   * only the photoless BRANCH of each card/detail screen was ever exercised
#
# Uses the repo's own fixture rather than the main seed's loremflickr fetch: e2e
# seeding must be deterministic and work offline, and a network hiccup must never
# be the reason a QA run reports a UI defect. Three copies per listing so the
# gallery has real pages to swipe; identical bytes are fine — the flows assert
# page COUNT and navigation, not that the pictures differ.
E2E_PHOTO = Rails.root.join("spec/fixtures/files/test_image.jpg")

if File.exist?(E2E_PHOTO)
  # Drafts were excluded here, which made the PUBLISH path unseedable. Publishing
  # requires at least one photo (Listing#photo_required_to_publish, and now the
  # mobile client's own pre-check), so every flow that opens a SEEDED draft and
  # publishes it was blocked before it started — lifecycle_publish among them, and
  # the failure looked like a broken publish button rather than a fixture with no
  # photo. One draft gets photos so the happy path is reachable; the other stays
  # photoless deliberately, because "Publish is refused, and says which field is
  # missing" is real behaviour that deserves a fixture too.
  photo_targets = Listing.where(user: seller)
                         .where(status: [ :active, :reserved, :sold ])
                         .limit(6)
                         .to_a
  # Prefer the NAMED fixture over "lowest id". Flows have to be able to target this
  # listing, and the lowest-id draft changes as create/edit flows add their own.
  publishable_draft = Listing.find_by(user: seller, title: "Ready To Publish Draft") ||
                      Listing.where(user: seller, status: :draft).order(:id).first
  photo_targets << publishable_draft if publishable_draft

  # SF-QA1 — the five sell-flow fixtures, BY NAME. The `limit(6)` above is a
  # fixed budget the same six listings have held since the day they were first
  # seeded (`next if listing.images.attached?` skips them, but they still fill
  # the six slots), so a listing added later can never win a photo through it.
  # These five are asserted on and screenshotted by the sell-flow QA run, and a
  # photoless card renders as the grey "no photo" box.
  photo_targets += Listing.where(user: seller, title: SELL_FLOW_FIXTURE_TITLES).to_a

  # ...and COORDINATES, not just a photo. `e2e_listing` sets `location` as free text
  # ("Kandahar, City Center") and no lat/long at all, but publishing requires an
  # exact pin: getPublishBlockers(mode: "publish") reports a `location` blocker
  # without one, and the API agrees. A draft with a photo and no pin is still
  # unpublishable, so the photo alone did not make the publish path reachable —
  # draft_lifecycle and lifecycle_publish would both still have been refused.
  #
  # Kabul city centre, matching where the rest of the e2e fixtures claim to be.
  if publishable_draft && publishable_draft.latitude.blank?
    publishable_draft.update_columns(latitude: 34.5553, longitude: 69.2075)
    puts "  pinned #{publishable_draft.title} at Kabul (publishable draft)"
  end
  attached_count = 0
  storage_denied = false

  photo_targets.each do |listing|
    next if listing.images.attached?

    begin
      3.times do |i|
        listing.images.attach(
          io: File.open(E2E_PHOTO),
          filename: "e2e-#{listing.id}-#{i}.jpg",
          content_type: "image/jpeg"
        )
      end
      attached_count += 1
    rescue Errno::EACCES, Errno::EPERM => e
      # Seeding must NEVER abort on a storage-permission problem. It happened:
      # `storage/` is owned by the host user but its subdirectories were created
      # by root (a Docker container writing into the bind mount), so the
      # host-run Rails cannot mkdir inside them — and since ActiveStorage keys
      # hash into those existing directories, most attachments fail. That took
      # the whole `reset_e2e` down with it, which is far worse than photo-less
      # fixtures: every QA flow depends on this task completing.
      #
      # Fix for the environment (needs root, so it is not done here):
      #   sudo chown -R "$USER" hatiwal-api/storage
      storage_denied = true
      warn "  ! photo attach denied (#{e.class}) — see storage ownership note above"
      break
    end
  end

  # A HALF-attached image is worse than no image. `images.attach` creates the
  # blob row and then writes the file, so a storage error between the two leaves
  # an attachment the API will serve a URL for and then fail to fulfil. Those
  # dangling rows produced 14 HTTP 500s in 40 minutes of QA
  # (ActiveStorage::FileNotFoundError from the variant redirect), and the mobile
  # client could only report them as network errors.
  #
  # So: verify every blob's file really landed, and purge the ones that did not.
  # Photo-less fixtures are a known, announced state; fixtures that lie are not.
  dangling = ActiveStorage::Blob.find_each.reject { |b| b.service.exist?(b.key) }
  if dangling.any?
    # Purge the ATTACHMENT, not the blob. `Blob#purge` is `destroy` with a bare
    # `rescue ActiveRecord::InvalidForeignKey`, so on a blob that is still
    # attached it raises, swallows, and reports success while deleting nothing —
    # verified live: purge returned without error and the row was still there.
    dangling.each do |blob|
      blob.attachments.each(&:purge)
      blob.purge if ActiveStorage::Blob.exists?(blob.id)
    end
    puts "  purged #{dangling.size} attachment(s) whose file never reached storage"
  end

  if storage_denied
    puts "  photos SKIPPED: ActiveStorage cannot write under storage/ as this user."
    puts "                  Listings stay photo-less; gallery flows will not pass."
    puts "                  Fix: sudo chown -R \"$USER\" storage"
  else
    puts "  attached 3 photos to #{attached_count} listing(s)"
  end
else
  puts "  WARN: #{E2E_PHOTO} missing — listings stay photo-less"
end

# =============================================================================
puts "=== E2E Seed: Multi-quantity conversation (docs/SPIKE_LISTING_QUANTITY.md) ==="
# =============================================================================
# The buyer picker only offers CONVERSATION PARTICIPANTS (Transaction enforces
# it), so without a thread on the multi-unit listing the "How many did you sell?"
# field is unreachable in any E2E flow — the field only renders once a real buyer
# is selected.

multi_unit_listing = Listing.find_by(user: seller, title: "Phone Case Silicone Clear - Wholesale")
if multi_unit_listing
  if Conversation.exists?(listing: multi_unit_listing, buyer: buyer)
    puts "  multi-quantity conversation already present"
  else
    mq_convo = Conversation.create!(listing: multi_unit_listing, buyer: buyer, seller: seller)
    Message.create!(conversation: mq_convo, user: buyer, kind: :text,
                    body: "Do you have 3 of these? I want three.")
    # A SELLER REPLY, so this conversation is not one-sided.
    #
    # With only the buyer's message it had no INBOUND message from the buyer's
    # point of view, and `mark_unread` nulls read_at on the latest inbound message
    # — so on this conversation it touched 0 rows and still answered 204 (UI-027).
    # Whenever a flow bumped this thread to the top of the list (composer_draft
    # posts to it) or archived the thread above it (conversation_archive), the
    # three unread-badge flows long-pressed THIS row and could never get a badge
    # back. They failed on the app being unable to do something the fixture had
    # made impossible.
    #
    # A seller who is asked "do you have 3?" answering is also simply realistic.
    #
    # READ, though. The requirement above is that an inbound message EXISTS, not
    # that it is unread: `mark_unread` nulls read_at on the latest inbound message,
    # so it works just as well on a read one. Left unread, this reply is a permanent
    # unread badge in the buyer's inbox, and chat/conversation_read_status ends by
    # asserting `notVisible: unread-badge-\d+` — which this fixture made impossible.
    # It failed on exactly that, with this conversation the only unread one in the
    # database. Same fix as the disposable conversations further down.
    Message.create!(conversation: mq_convo, user: seller, kind: :text,
                    body: "Yes, I have 15 in stock. How many do you need?",
                      read_at: Time.current)
    puts "  created multi-quantity conversation with #{buyer.email} (both sides)"
  end
else
  puts "  WARN: multi-unit listing not found — multi-quantity conversation skipped"
end

# =============================================================================
puts "=== E2E Seed: Disposable listings for DESTRUCTIVE flows ==="
# =============================================================================
# Flows that mark a listing sold or reserved, unpublish it, or delete it need a
# subject they are allowed to ruin. Fourteen of them used to grab "whichever
# listing comes first", which is a SHARED fixture — so a lifecycle flow would set
# a seeded listing to sold, and every later flow expecting it active failed. The
# damage lasted until the next re-seed, so the cause surfaced nowhere near the
# flow responsible. delete_listing was the extreme case: it removed
# "iPhone 12 Pro - 128GB" outright.
#
# These exist purely to be destroyed. NOTHING may assert their presence, their
# status or their count — one per destructive flow, named after it, so a failure
# points at its owner instead of at a random neighbour.
#
# They are created ACTIVE directly. The app's publish blockers (a photo and a map
# pin) are UI rules enforced by getPublishBlockers; the database has no such
# constraint, and requiring each flow to publish through the form would add ~90s
# apiece to test something those flows are not about.
# Each entry is [flow name, starting status]. The status MATTERS: lifecycle_sold
# taps the "Reserved" filter and then the primary action, which is "Mark as Sold"
# only for a reserved listing — handing it an active one would fail for the wrong
# reason. Every other flow here starts from the Active tab.
#
# rate_buyer_after_sale is deliberately absent: it needs a completed sale with an
# identified buyer, which is a transaction fixture rather than a spare listing, and
# it already has one.
# ── Language: reset to English every seed ────────────────────────────────────
# `preferred_language` is applied on login (applyLanguageFromUser), so a run that
# ends with the e2e accounts set to Pashto or Dari starts the NEXT run in that
# locale. Every handle on the login screen used to be English copy, which made
# that unrecoverable: the suite could not sign in, and signing in is the only
# route back to a language picker. Six seller flows died that way — three of them
# spending ~7 minutes each before giving up.
#
# The mobile app also keeps its own AsyncStorage copy, so this is not the whole
# story on a warm device — but it is the half the seed owns, and it means a fresh
# login always lands in English.
# ── An UNCONFIRMED account, so the confirm-email prompt can be tested ────────
# The prompt only renders when `email_confirmed` is false, and every seeded
# account is confirmed (the backfill migration confirmed all pre-existing users).
# Without a deliberately unconfirmed fixture there is no way to exercise the
# banner or its resend button on a device at all.
#
# A DEDICATED account, not one of the three above: making buyer@ unconfirmed would
# put the banner on the profile screen that dozens of other flows assert against.
unconfirmed = e2e_user(
  email: "unconfirmed@hatiwal.test", firstname: "Nasrin", lastname: "Ahmadi",
  city: "Kabul", province: "Kabul"
)
if unconfirmed.confirmed_at.present?
  unconfirmed.update_columns(confirmed_at: nil)
  puts "  unconfirmed@hatiwal.test reset to UNCONFIRMED (confirm-email prompt fixture)"
end

reset_langs = User.where(email: %w[buyer@hatiwal.test seller@hatiwal.test newbuyer@hatiwal.test])
                  .where.not(preferred_language: "en")
                  .update_all(preferred_language: "en")
puts "  reset preferred_language -> en for #{reset_langs} e2e account(s)"

# ── Blocks: cleared every seed ────────────────────────────────────────────────
# A block HIDES the blocked user's listings from the blocker's feed. So a block
# flow that fails before its unblock step leaves the seller blocked, and every
# later flow that needs one of their listings fails with "No visible element
# found: Wool Blanket Handmade King Size" — a missing-fixture message for a
# fixture that is present and merely hidden. That is exactly how report_listing
# failed after block_user_hides_listings died mid-flow.
#
# Only the two e2e accounts' blocks are removed; real users' blocks are untouched.
e2e_user_ids = [ buyer.id, seller.id ]
removed_blocks = Block.where(blocker_id: e2e_user_ids)
                      .or(Block.where(blocked_id: e2e_user_ids))
                      .destroy_all
                      .size
puts "  cleared #{removed_blocks} block(s) between the e2e accounts"

# Reports leak the same way blocks do, with a sharper edge: a Report is UNIQUE per
# reporter+target (Report validates it with `message: :already_reported`), so the
# FIRST run of a report flow creates the row and every run after it is answered with
# report.errors.duplicate instead of report.success.
#
# chat/report_participant failed exactly that way once the buyer->seller "fraud" row
# existed. report/report_user and report/report_user_then_block could not pass at
# all while it does: ReportSheet.tsx offers the "Block this user?" prompt from inside
# the mutation's onSuccess, so on the duplicate path everything after it is
# unreachable. See RIG-004 in hatiwal-mobile/qa/UI_FINDINGS.md.
#
# Only reports FILED BY the e2e accounts are removed. Reports filed by real users
# against them are left untouched, so no moderation data is ever destroyed.
removed_reports = Report.where(reporter_id: e2e_user_ids).destroy_all.size
puts "  cleared #{removed_reports} report(s) filed by the e2e accounts"

# A DISPOSABLE MULTI-UNIT listing, for the off-platform partial-sale flow
# (maestro/seller/multi_quantity_offplatform_sale.yaml). Deliberately NOT the Phone Case
# that multi_quantity_partial_sale draws down: two flows selling out of one batch means
# whichever runs second asserts against a stock it did not set.
#
# The stock is RESTORED every seed, the same way the expiry fixture's date is. Selling
# units is precisely what the flow does, so without this it would work exactly once.
e2e_listing(
  user:        seller,
  title:       "QA Disposable offplatform_units",
  price:       900,
  category:    electronics,
  status:      :active,
  quantity:    8,
  description: "Disposable multi-unit fixture. A flow sells SOME of it to a buyer who " \
               "is not on Hatiwal; the stock is reset to 8 on every seed.",
  location:    "Kabul"
)
offplatform_units = Listing.find_by(user: seller, title: "QA Disposable offplatform_units")
if offplatform_units &&
   (offplatform_units.quantity != 8 ||
    offplatform_units.sold_units.to_i.positive? ||
    offplatform_units.status.to_sym != :active)
  offplatform_units.update_columns(
    quantity:   8,
    sold_units: 0,
    status:     Listing.statuses[:active],
    sold_at:    nil
  )
  puts "  reset multi-unit disposable -> 8 units, 0 sold, active"
end

DISPOSABLE_LISTINGS = [
  [ "lifecycle_reserve",       :active ],
  [ "lifecycle_sold",          :reserved ],
  [ "lifecycle_unpublish",     :active ],
  [ "mark_sold_with_buyer",    :active ],
  [ "reserved_buyer",          :active ],
  [ "saved_listing_goes_sold", :active ],
  [ "my_listing_detail_view",  :active ],
  # chat/conversation_delete SOFT-DELETES the thread it acts on, so it must own
  # one. It previously targeted the shared "Xiaomi Redmi Note 11" thread on the
  # grounds that a SOLD listing is safe to consume -- but deleting is not the
  # same as consuming: `buyer_deleted_at` made that thread invisible to the
  # buyer permanently (recorded 2026-09-01 17:54), so every later run failed on
  # `No visible element found: "Xiaomi Redmi.*"` while the app behaved exactly
  # as designed.
  [ "conversation_delete",     :active ],
  # chat/scroll_to_latest and chat/jump_to_latest each send 6-8 messages to build
  # a thread long enough to scroll, so they must NOT do it in a shared thread.
  # They were using "Phone Case Silicone Clear", which six other flows depend on
  # — and their outbound filler pushed that thread's latest INBOUND message far
  # into the history, which is what broke chat/mark_read_end_to_end: the
  # mark-unread helper nulls read_at on the latest inbound message, so the
  # "Unread messages" divider ended up dozens of screens above the fold and a 20s
  # scrollUntilVisible could never reach it.
  [ "scroll_to_latest",        :active ]
].freeze

DISPOSABLE_LISTINGS.each_with_index do |(owner, status), i|
  title = "QA Disposable #{owner}"

  e2e_listing(
    user:        seller,
    title:       title,
    price:       1000 + (i * 100),
    category:    electronics,
    status:      status,
    description: "Disposable fixture for maestro/**/#{owner}.yaml. Safe to reserve, " \
                 "sell, unpublish or delete — no flow asserts anything about it.",
    location:    "Kabul"
  )

  # RESET the status every seed. `e2e_listing` is create-if-missing, so without
  # this a disposable listing is single-use: the flow that owns it sells or
  # unpublishes it, and every later cycle finds it in the wrong state and fails
  # for a reason that has nothing to do with the code under test. Being
  # restorable is the whole point of a disposable fixture.
  #
  # Recreate it outright if a flow DELETED it.
  listing = Listing.find_by(user: seller, title: title)
  if listing.nil?
    e2e_listing(
      user: seller, title: title, price: 1000 + (i * 100), category: electronics,
      status: status, location: "Kabul",
      description: "Disposable fixture for maestro/**/#{owner}.yaml."
    )
  elsif listing.status.to_sym != status
    listing.update_columns(
      status:      Listing.statuses[status],
      published_at: %i[active reserved sold].include?(status) ? 2.days.ago : nil,
      reserved_at: status == :reserved ? 1.day.ago : nil,
      sold_at:     status == :sold ? 1.day.ago : nil
    )
    puts "  reset #{title} -> #{status}"
  end

  # A CONVERSATION for the flows that need to identify a real buyer.
  #
  # mark_sold_with_buyer and reserved_buyer pick a committed buyer from the
  # listing's own conversations, so their disposable fixture is useless without
  # one — which is why both flows still reached for the shared
  # "Lenovo ThinkPad Laptop Core i5 8GB" AFTER searching for their disposable,
  # a search that had just filtered that listing out of the list. They failed on
  # `No visible element found` for a listing the search itself had hidden.
  #
  # Only these two get one: an empty conversation list is what the other
  # disposables are for, and giving every fixture a conversation would change
  # what those flows see.
  next unless %w[mark_sold_with_buyer reserved_buyer conversation_delete scroll_to_latest].include?(owner)

  listing = Listing.find_by(user: seller, title: title)
  next if listing.nil?

  # UN-DELETE and UN-ARCHIVE before concluding it already exists.
  #
  # `Conversation.exists?` was the entire guard, so a thread a flow had SOFT-
  # deleted counted as present and was never repaired: the row survived with
  # `buyer_deleted_at` set, the index scope (`not_deleted_for`) hid it from the
  # buyer, and the owning flow failed every run until someone wiped the whole
  # database. A disposable fixture that cannot come back is not disposable --
  # the comment above makes exactly this point about listing STATUS, and it has
  # to hold for a conversation's delete/archive flags too.
  existing = Conversation.find_by(listing: listing, buyer: buyer)
  if existing
    stale = existing.slice(:buyer_deleted_at, :seller_deleted_at,
                           :buyer_archived_at, :seller_archived_at).compact
    if stale.any?
      existing.update_columns(buyer_deleted_at: nil, seller_deleted_at: nil,
                              buyer_archived_at: nil, seller_archived_at: nil)
      puts "  restored conversation on #{title} (cleared #{stale.keys.join(', ')})"
    end
    next
  end

  convo = Conversation.create!(listing: listing, buyer: buyer, seller: seller)
  Message.create!(conversation: convo, user: buyer, kind: :text,
                  body: "Is this still available? I can collect today.")
  # READ, deliberately. The seller reply is INBOUND for the buyer, so leaving it
  # unread plants a permanent unread badge on the buyer's inbox — and any flow
  # asserting "no unread badge anywhere" then fails on a fixture rather than on
  # anything it did. chat/conversation_read_status died exactly that way: it marked
  # one conversation unread, read it, and still saw a badge, because THIS
  # conversation was holding one the whole time.
  #
  # These flows need the conversation to exist so a buyer can be identified; the
  # read state is irrelevant to them.
  Message.create!(conversation: convo, user: seller, kind: :text,
                  body: "Yes — when suits you?", read_at: Time.current)
  puts "  conversation seeded on #{title} (buyer identifiable, no unread left behind)"
end
puts "  #{DISPOSABLE_LISTINGS.size} disposable listings ready"

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
    u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
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
puts "=== E2E Seed: Transaction (sold/bought trust stats — TASK-TX02) ==="
# =============================================================================
# Attaches a `sold` Transaction to the already-seeded sold listing so
# seller@hatiwal.test.sold_count and buyer@hatiwal.test.bought_count are both
# guaranteed >= 1 in every Maestro E2E run (the "Sold N · Bought N" trust
# badge / profile stats row have a non-empty state to assert against).
# newbuyer@hatiwal.test deliberately has NO transaction history — it is the
# fixture for asserting the badge/stat is HIDDEN when the count is 0.

tx_listing = Listing.find_by(user: seller, title: "Xiaomi Redmi Note 11 128GB")

if tx_listing
  # The buyer must be a conversation participant on this listing (Transaction
  # model validation) — create one if it doesn't already exist.
  unless Conversation.exists?(listing: tx_listing, seller: seller, buyer: buyer)
    Conversation.create!(listing: tx_listing, seller: seller, buyer: buyer)
    puts "  created conversation for the sold-listing transaction"
  end

  unless Transaction.exists?(listing: tx_listing, seller: seller, buyer: buyer, status: :sold)
    Transaction.create!(
      listing:      tx_listing,
      seller:       seller,
      buyer:        buyer,
      final_price:  tx_listing.price,
      currency:     tx_listing.currency,
      status:       :sold,
      completed_at: tx_listing.sold_at || 3.days.ago
    )
    puts "  seeded sold Transaction: #{tx_listing.title} (seller sold_count / buyer bought_count both >= 1)"
  else
    puts "  sold Transaction already present for #{tx_listing.title}"
  end
else
  puts "  WARN: Xiaomi Redmi Note 11 listing not found — transaction seed skipped"
end

# =============================================================================
puts "=== E2E Seed: Sell-flow states (SF-QA1 / card #296) ==="
# =============================================================================
# The five states the sell-flow redesign shipped (docs/SELL_FLOW_REDESIGN.md,
# backend commit c5e155c) and NOTHING seeded — so its two headline cases could
# not be asserted on a device at all. QA would have skipped them in silence and
# reported a pass (hatiwal-mobile/docs/SELL_FLOW_QA_PLAN.md §4.2).
#
#   1. an open HOLD on a live batch      -> "N held · N available" (buyer),
#                                           "N held for {name}" (seller),
#                                           release-hold from the chat thread
#   2. a SOLD-OUT batch                  -> the terminal state
#   3. sold out, then quantity RAISED     -> the owner's own bug report (SF-B6)
#   4. one batch, SEVERAL buyers          -> the Sales ledger (SF-B5), which had
#                                           nothing realistic to render
#   5. a sold sale carrying a REVIEW      -> void/reassign refused with
#                                           `sale_has_review`, quantity edit
#                                           still allowed (SF-B4)
#
# THE INVARIANTS every fixture here satisfies, because the backend now enforces
# them and a fixture that breaks one is a state the app can never produce:
#
#   * sold_units <= quantity          — DB CHECK `listings_sold_units_within_quantity`
#   * available_units >= held_units   — asserted in Listing (SF-B9)
#   * at most ONE open (reserved) transaction per listing — partial unique index
#     `index_transactions_on_listing_id_while_open`
#
# A BATCH WITH A HOLD DELIBERATELY KEEPS `status: active` (SF-B2). 15 pairs do
# not leave the market because a buyer reserved 10 of them, so `status` is NOT
# the signal that a hold exists — `held_units` is. Forcing fixture 1 to
# `reserved` would seed exactly the state three of the bugs in that commit came
# from, and `place hold`/`release hold` would then be tested against a listing
# the app never produces.
#
# WHY THE SOLD ROWS AVOID buyer@hatiwal.test. A sold Transaction with a real
# counterparty creates a PENDING REVIEW for both sides, and
# maestro/reviews/pending_reviews_nudge.yaml ends with
# `assertNotVisible: "Rate your recent deals"` as buyer@hatiwal.test — one extra
# sold row against that account would leave a permanent nudge and fail a flow
# that has nothing to do with these fixtures. So the sold rows use the synthetic
# e2ebuyerN accounts (already seeded above for the response-rate badge, and no
# flow logs in as them); buyer@hatiwal.test gets only the RESERVED hold, which is
# not a completed sale and creates no pending review. newbuyer@hatiwal.test is
# untouched by design — it is the zero-history fixture.

sell_flow_buyers = {
  "buyer"      => buyer,
  "e2ebuyer2"  => User.find_by(email: "e2ebuyer2@hatiwal.test"),
  "e2ebuyer3"  => User.find_by(email: "e2ebuyer3@hatiwal.test"),
  "e2ebuyer4"  => User.find_by(email: "e2ebuyer4@hatiwal.test"),
  "e2ebuyer5"  => User.find_by(email: "e2ebuyer5@hatiwal.test")
}.freeze

# The declared shape of each fixture's ledger. `buyer: nil` is the deliberate
# "sold to someone not on Hatiwal" row SF-B3 made recordable.
SELL_FLOW_LEDGERS = {
  "Winter Gloves Wholesale Box - 15 Pairs" => {
    quantity: 15, status: :active,
    sales: [
      { buyer: "buyer", units: 10, status: :reserved, days_ago: 2,
        ask:   "I have a small shop in Kabul — can you hold 10 pairs for me until Thursday?",
        reply: "Done, 10 pairs are held for you. The other 5 stay on sale." }
    ]
  },
  "Solar Lantern Rechargeable - Batch of 6" => {
    quantity: 6, status: :sold,
    sales: [
      { buyer: "e2ebuyer5", units: 6, status: :sold, days_ago: 4,
        ask:   "Are all six still available? I want the whole batch.",
        reply: "Yes, all six. I can meet you tomorrow morning." }
    ]
  },
  "School Backpack Bulk Restock - 20 Bags" => {
    quantity: 20, status: :active,
    sales: [
      { buyer: "e2ebuyer2", units: 15, status: :sold, days_ago: 6,
        ask:   "I need 15 bags for a school. Can you do all of them?",
        reply: "All 15 are yours. I will bring them in two trips." }
    ]
  },
  "Steel Thermos Flask 1L - Bulk Batch" => {
    quantity: 15, status: :active,
    sales: [
      { buyer: "e2ebuyer2", units: 2, status: :sold, days_ago: 7,
        ask:   "Two flasks please, are they the tall ones?",
        reply: "Yes, one litre. Two is fine." },
      { buyer: "e2ebuyer3", units: 3, status: :sold, days_ago: 4,
        ask:   "Do you still have three left for me?",
        reply: "Three are ready for you." },
      # No account on the other side — a neighbour who is not on Hatiwal. Before
      # SF-B3 this sale was a silent no-op with no ledger row to correct.
      #
      # Deliberately the NEWEST row, so `Listing#current_sale` surfaces it and the
      # seller's own card renders a sale with `buyer: nil` — the nil-safe path
      # SF-B3 added to ListingSerializer::SALE_FIELD and SaleBuyerCard, which no
      # fixture could reach before. The two named rows below it keep the ledger
      # itself mixed.
      { buyer: nil, units: 1, status: :sold, days_ago: 2 }
    ]
  },
  "Electric Kettle 1.8L Stainless - Bulk 10" => {
    quantity: 10, status: :active,
    sales: [
      { buyer: "e2ebuyer4", units: 3, status: :sold, days_ago: 5,
        ask:   "Three kettles for my guesthouse — is the price the same for three?",
        reply: "Same price each. Three it is." }
    ]
  }
}.freeze

# A conversation with a REAL exchange, not a bare row.
#
# Two reasons it cannot be message-less. `Transaction` requires the buyer to be a
# conversation participant on the listing (`buyer_is_conversation_participant`),
# which a bare row satisfies — but `User#compute_seller_response_stats` counts
# every conversation from the last 90 days in the DENOMINATOR of the reply rate
# and only a conversation with a reply in the numerator, so five empty threads
# would have quietly cut seller@hatiwal.test's "N% reply rate" (the figure
# browse/seller_response_rate_badge asserts) for no reason. The 20-minute reply
# also keeps the median inside `:within_one_hour`.
#
# BOTH sides carry read_at. An unread INBOUND message is a permanent unread badge
# in that account's inbox, and chat/conversation_read_status ends by asserting
# `notVisible: unread-badge-\d+` for buyer@hatiwal.test — the exact trap the
# multi-quantity conversation above documents at length.
def e2e_sale_conversation(listing:, seller:, buyer:, ask:, reply:)
  existing = Conversation.find_by(listing: listing, seller: seller, buyer: buyer)
  return existing if existing

  convo     = Conversation.create!(listing: listing, seller: seller, buyer: buyer)
  opened_at = 3.days.ago

  bm = Message.new(conversation: convo, user: buyer, kind: :text,
                   body: ask, read_at: opened_at + 5.minutes)
  bm.created_at = opened_at
  bm.updated_at = opened_at
  bm.save!

  sr = Message.new(conversation: convo, user: seller, kind: :text,
                   body: reply, read_at: opened_at + 30.minutes)
  sr.created_at = opened_at + 20.minutes
  sr.updated_at = sr.created_at
  sr.save!

  convo.update!(last_message_at: sr.created_at)
  convo
end

# Rebuild ONE fixture's ledger from scratch, every seed.
#
# Create-if-missing is not enough here, for the same reason DISPOSABLE_LISTINGS
# above resets its statuses: every one of these fixtures exists to be MUTATED by
# the flow that targets it (release the hold, void a sale, raise the quantity).
# The difference is that these are ASSERTED ON, so a drifted fixture does not
# merely waste a run — it produces a wrong verdict about the feature. Wiping and
# rewriting the ledger means every cycle starts from the declared shape.
#
# `update_columns`, not `update!`: this writes the intended END state directly.
# `update!` would fire SF-B6's `reconcile_status_after_quantity_change`
# (after_update on `saved_change_to_quantity?`) and flip fixture 3 straight back
# to `sold` — the very bug that fixture exists to prove is fixed.
def e2e_sell_flow_ledger(seller:, title:, quantity:, status:, sales:, buyers:)
  listing = Listing.find_by(user: seller, title: title)
  if listing.nil?
    puts "  WARN: #{title} not found — sell-flow ledger skipped"
    return nil
  end

  # Cascades to `reviews` (Transaction has_many :reviews, dependent: :destroy),
  # which fixture 5 deliberately carries. The trust counters those rows bumped
  # are recomputed from source at the end of this section, so nothing drifts
  # across re-seeds.
  listing.sale_transactions.destroy_all

  sold      = sales.select { |s| s[:status] == :sold }
  units     = sold.sum { |s| s[:units] }
  oldest    = sales.map { |s| s[:days_ago] }.max

  listing.update_columns(
    quantity:     quantity,
    sold_units:   units,
    status:       Listing.statuses[status],
    published_at: (oldest + 2).days.ago,
    # Cleared here and re-derived below by `reconcile_hold_stamp!` once this
    # fixture's ledger rows exist. SF-B10 fixed the gap this used to document:
    # a held batch stays `active`, and `reserved_at` is now dated from the HOLD
    # (its Transaction's created_at) rather than from the status — so a held
    # batch DOES carry a "held since" date, and the fixture has to match.
    reserved_at:  nil,
    sold_at:      status == :sold ? sold.map { |s| s[:days_ago] }.min&.days&.ago : nil,
    # nil reads as "never expires" to `not_expired`, so these five can never
    # drop out of `browsable` or into the seller's Expired tab mid-cycle. The
    # expiry fixture is "Expired Winter Coat Size L" and stays the only one.
    expires_at:   nil,
    removed_at:   nil
  )
  listing.reload

  sales.each do |sale|
    sale_buyer = sale[:buyer] && buyers.fetch(sale[:buyer])
    if sale_buyer
      e2e_sale_conversation(
        listing: listing, seller: seller, buyer: sale_buyer,
        ask: sale[:ask], reply: sale[:reply]
      )
    end

    txn = listing.sale_transactions.new(
      seller:       seller,
      buyer:        sale_buyer,
      final_price:  listing.price,
      currency:     listing.currency,
      status:       sale[:status],
      quantity:     sale[:units],
      completed_at: sale[:status] == :sold ? sale[:days_ago].days.ago : nil
    )
    txn.created_at = sale[:days_ago].days.ago
    txn.updated_at = txn.created_at
    txn.save!
  end

  # SF-B10 — the rows above are written straight to the table, so nothing dated
  # the hold on the way in. One call derives it from the ledger we just built
  # (the open hold's created_at, or nil when this fixture has no hold), which is
  # exactly what the app's own reserve/release paths do.
  listing.reconcile_hold_stamp!

  listing.reload
  puts "  #{title}"
  puts "    #{listing.status} · quantity #{listing.quantity} · sold_units #{listing.sold_units} · " \
       "available #{listing.available_units} · held #{listing.held_units} · " \
       "sales #{listing.sales_count} of #{listing.sale_transactions.count} row(s) · " \
       "held since #{listing.reserved_at&.to_date || '—'}"
  listing
end

SELL_FLOW_LEDGERS.each do |title, spec|
  e2e_sell_flow_ledger(
    seller: seller, title: title, quantity: spec[:quantity],
    status: spec[:status], sales: spec[:sales], buyers: sell_flow_buyers
  )
end

# ── Fixture 5's REVIEW ───────────────────────────────────────────────────────
# Submitted through Review#submit! rather than written straight to the column, so
# the fixture is produced by the same path the app uses: the first review stays
# hidden (double-blind), the second reveals BOTH and recomputes each reviewee's
# aggregates.
#
# A COMPLETE PAIR, not one side. A lone review leaves the other party with a
# pending review forever, and the pending-review nudge is asserted on elsewhere
# (see the note at the top of this section). A pair leaves nothing pending for
# anyone, which is also the realistic end state of a finished deal.
reviewed_sale = Transaction.joins(:listing)
                           .find_by(listings: { title: "Electric Kettle 1.8L Stainless - Bulk 10" },
                                    status: :sold)

if reviewed_sale.nil?
  puts "  WARN: reviewed-sale fixture not found — review skipped"
elsif reviewed_sale.reviews.exists?
  puts "  reviewed sale already carries #{reviewed_sale.reviews.count} review(s)"
else
  Review.new(
    sale: reviewed_sale, reviewer: reviewed_sale.buyer, reviewee: reviewed_sale.seller,
    role: :of_seller, rating: 5, comment: "Kettles were exactly as described. Easy meetup."
  ).submit!
  Review.new(
    sale: reviewed_sale, reviewer: reviewed_sale.seller, reviewee: reviewed_sale.buyer,
    role: :of_buyer, rating: 5, comment: "Came on time and took all three. Good buyer."
  ).submit!
  puts "  reviewed sale ##{reviewed_sale.id} now carries a revealed double-blind pair " \
       "(void / reassign must answer 422 sale_has_review)"
end

# ── Trust counters: recomputed, not left to the increments ────────────────────
# `Transaction#bump_trust_counters!` fires on every sold row this section
# creates, and the `destroy_all` above does not compensate (only
# Transaction#void! does). Left alone, sold_count and bought_count would climb
# by five on every single re-seed. `recompute_transaction_counters!` counts
# DISTINCT sold listing_ids from source — the same repair
# `bin/rails transactions:recompute_counters` performs — so the figures are
# identical no matter how many times this file has been loaded.
#
# Scoped to the accounts this section touched. newbuyer@hatiwal.test is
# deliberately absent: it is the fixture for "the stat is HIDDEN when the count
# is 0" (maestro/profile/transaction_stats_hidden_when_zero.yaml).
[ seller, *sell_flow_buyers.values.compact ].uniq.each(&:recompute_transaction_counters!)
puts "  recomputed trust counters: seller sold_count=#{seller.reload.sold_count}, " \
     "buyer bought_count=#{buyer.reload.bought_count}"

# ── The invariants, checked rather than asserted in prose ────────────────────
# Cheap, and it runs on every seed. A fixture that violates one of these is a
# state the app can never produce, so QA measuring against it proves nothing —
# better to fail the seed loudly here than to hand the night a fixture that lies.
sell_flow_violations = Listing.where(user: seller, title: SELL_FLOW_LEDGERS.keys).filter_map do |l|
  problems = []
  problems << "sold_units #{l.sold_units} > quantity #{l.quantity}" if l.sold_units > l.quantity
  problems << "held #{l.held_units} > available #{l.available_units}" if l.held_units > l.available_units
  open_rows = l.sale_transactions.reserved.count
  problems << "#{open_rows} open transactions" if open_rows > 1
  "#{l.title}: #{problems.join(', ')}" if problems.any?
end

if sell_flow_violations.any?
  raise "Sell-flow fixtures violate an enforced invariant:\n  #{sell_flow_violations.join("\n  ")}"
end
puts "  invariants OK: sold_units <= quantity, available_units >= held_units, <= 1 open hold each"


# =============================================================================
puts "=== E2E Seed: seller@hatiwal.test's own Buying thread (TASK-R517) ==="
# =============================================================================
# Every other conversation above puts seller@hatiwal.test on the SELLER side
# only (all seeded listings are owned by `seller`) — there was no fixture
# where the SAME account also has an active BUYING thread, so the
# Buying/Selling role-filter Maestro flow had nothing deterministic to assert
# beyond "the chips exist". `newbuyer@hatiwal.test` gets one listing of its
# own and seller@hatiwal.test starts a conversation on it, giving
# seller@hatiwal.test both role types from a single login:
#   - Selling: the response-badge + sold-transaction conversations above
#   - Buying:  this one thread, where seller@hatiwal.test is the buyer

newbuyer_listing_title = "Mountain Bike 26-inch Steel Frame"

newbuyer_listing = Listing.find_or_create_by!(user: newbuyer, title: newbuyer_listing_title) do |l|
  l.category    = vehicles
  l.description = "Well-maintained mountain bike, 21-speed, recently serviced brakes and chain."
  l.price        = 9_500
  l.currency     = "AFN"
  l.status       = :active
  l.location     = "Herat"
  l.views_count  = rand(5..50)
  l.published_at = rand(1..10).days.ago
end
puts "  newbuyer listing ready: #{newbuyer_listing.title}"

seller_buying_convo = Conversation.find_by(listing: newbuyer_listing, buyer: seller, seller: newbuyer)
unless seller_buying_convo
  seller_buying_convo = Conversation.create!(listing: newbuyer_listing, buyer: seller, seller: newbuyer)
  buyer_msg_time = 1.day.ago
  bm = Message.new(conversation: seller_buying_convo, user: seller, body: "Hi, is the mountain bike still available?",
                    kind: :text)
  bm.created_at = buyer_msg_time
  bm.updated_at = buyer_msg_time
  bm.save!
  seller_buying_convo.update!(last_message_at: buyer_msg_time)
  puts "  created seller@hatiwal.test's Buying-side conversation on #{newbuyer_listing.title}"
else
  puts "  seller@hatiwal.test's Buying-side conversation already present"
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
puts "    sold_count (trust stat): #{seller.reload.sold_count}"
puts "  buyer@hatiwal.test    bought_count (trust stat): #{buyer.reload.bought_count}"
puts "  newbuyer@hatiwal.test bought_count (trust stat): #{newbuyer.reload.bought_count} (should be 0 — no history fixture)"
puts "  newbuyer@hatiwal.test — fresh account, nothing saved"
puts ""
puts "  Sell-flow fixtures (SF-QA1) — status · quantity · sold · available · held"
Listing.where(user: seller, title: SELL_FLOW_LEDGERS.keys).order(:id).each do |l|
  puts format(
    "    %-42s %-7s q=%-3d sold=%-3d avail=%-3d held=%-3d sales=%d",
    l.title[0, 42], l.status, l.quantity, l.sold_units, l.available_units, l.held_units, l.sales_count
  )
end
puts ""
puts "  Run E2E tests: maestro test hatiwal-mobile/maestro/"
puts "======================================"
