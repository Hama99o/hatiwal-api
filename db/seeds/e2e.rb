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

def e2e_listing(user:, title:, price:, category:, status:, description:, location:, latitude: nil, longitude: nil, quantity: 1)
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

# Multi-quantity (docs/SPIKE_LISTING_QUANTITY.md, Tier 1) — the reseller case
# the feature was built for: one listing, 15 identical units. Drives the "each"
# per-unit price, the stock pill, and the buyer picker's "How many did you sell?"
# field. Kept as the ONLY multi-unit fixture so every other flow keeps asserting
# the single-item majority case.
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
  publishable_draft = Listing.where(user: seller, status: :draft).order(:id).first
  photo_targets << publishable_draft if publishable_draft

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

DISPOSABLE_LISTINGS = [
  [ "lifecycle_reserve",       :active ],
  [ "lifecycle_sold",          :reserved ],
  [ "lifecycle_unpublish",     :active ],
  [ "mark_sold_with_buyer",    :active ],
  [ "reserved_buyer",          :active ],
  [ "saved_listing_goes_sold", :active ],
  [ "my_listing_detail_view",  :active ]
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
  next unless %w[mark_sold_with_buyer reserved_buyer].include?(owner)

  listing = Listing.find_by(user: seller, title: title)
  next if listing.nil? || Conversation.exists?(listing: listing, buyer: buyer)

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
puts "  Run E2E tests: maestro test hatiwal-mobile/maestro/"
puts "======================================"
