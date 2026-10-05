# =============================================================================
# Hatiwal QA seeds for the features in flight: LOC-1 (own address + guessed
# location), VER-1 (verification requests), SHOP-1 (shops, selling as).
#
# Run:  bundle exec rake db:seed:qa_features
#       (also run by `./qa/qa.sh seed` in hatiwal-mobile, after reset_e2e)
#
# Every account: <name>@hatiwal.test, password Password123!
#
# Rules this file keeps:
#   * IDEMPOTENT. Re-running puts every fixture back in its seeded state.
#   * NO SUPPORT THREADS (hatiwal-api/docs/SUPPORT_MESSAGING.md). Decisions are
#     written as rows, never through VerificationRequest#approve!/reject!/revoke!,
#     because those queue SupportNoticeJob. The end of the file checks it.
#   * FAKE documents only. db/seeds/qa_samples/*.png are generated placeholders
#     stamped "SAMPLE". The repo is public: never put a real ID or a real
#     person's photo here.
#   * Schema-tolerant: a section whose columns/tables have not landed yet is
#     skipped with a note, so this runs on main at any point while LOC-1 and
#     VER-1 are being built.
# =============================================================================

abort "qa_features seeds are for development/QA only" if Rails.env.production?

QA_PASSWORD = "Password123!".freeze
QA_SAMPLES  = Rails.root.join("db/seeds/qa_samples")
QA_PHOTO    = Rails.root.join("spec/fixtures/files/test_image.jpg")

# Province centres (the province's main city). Mazar-i-Sharif is in Balkh and
# Jalalabad in Nangarhar, matching how the rest of the seeds name provinces.
QA_PLACES = {
  kabul:     { province: "Kabul",     city: "Kabul",          latitude: 34.5553, longitude: 69.2075 },
  herat:     { province: "Herat",     city: "Herat",          latitude: 34.3529, longitude: 62.2040 },
  mazar:     { province: "Balkh",     city: "Mazar-i-Sharif", latitude: 36.7090, longitude: 67.1109 },
  jalalabad: { province: "Nangarhar", city: "Jalalabad",      latitude: 34.4265, longitude: 70.4515 },
  kandahar:  { province: "Kandahar",  city: "Kandahar",       latitude: 31.6289, longitude: 65.7372 },
  # Outside Afghanistan, Pakistan and Iran: must fall back to Kabul.
  dubai:     { province: "Dubai",     city: "Dubai",          latitude: 25.2048, longitude: 55.2708 }
}.freeze

def qa_user(email:, firstname:, lastname:, place: nil, avatar: false, language: "en")
  user = User.find_or_initialize_by(email: email)
  created = user.new_record?
  if created
    user.assign_attributes(
      firstname: firstname, lastname: lastname,
      password: QA_PASSWORD, password_confirmation: QA_PASSWORD,
      bio: "QA test account.", preferred_language: language, preferred_theme: "system",
      uid: email, provider: "email"
    )
    user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
    user.save!
  end

  # Reset the own address every run: flows change it through the Change sheet.
  own = place ? QA_PLACES.fetch(place) : {}
  user.update_columns(
    firstname: firstname, lastname: lastname,
    province: own[:province], city: own[:city],
    latitude: own[:latitude], longitude: own[:longitude],
    confirmed_at: user.confirmed_at || Time.current,
    preferred_language: language
  )

  if avatar && !user.avatar.attached?
    user.avatar.attach(qa_blob(QA_SAMPLES.join("avatar.png"), "qa-avatar.png", "image/png"))
  elsif !avatar && user.avatar.attached?
    user.avatar.purge
  end

  puts "  #{created ? 'created' : 'reset  '} #{email}"
  user
end

def qa_column?(model, column) = model.column_names.include?(column.to_s)

# A blob whose storage folder this user can write.
#
# Some storage/xx/ folders were created by root (a Docker container writing into
# the bind mount), so a random Active Storage key fails ~6% of the time with
# EACCES, and one failure aborted the whole seed. Instead of skipping photos
# (e2e.rb does), pick a key whose folders are writable. Disk service only; on any
# other service the key is left to Active Storage.
def qa_blob(path, filename, content_type)
  service = ActiveStorage::Blob.service
  key = nil
  if service.respond_to?(:root)
    20.times do
      candidate = ActiveStorage::Blob.generate_unique_secure_token(length: ActiveStorage::Blob::MINIMUM_TOKEN_LENGTH)
      dirs = [ File.join(service.root, candidate[0..1]), File.join(service.root, candidate[0..1], candidate[2..3]) ]
      parent_ok = File.writable?(service.root)
      ok = dirs.all? do |dir|
        writable = File.directory?(dir) ? File.writable?(dir) : parent_ok
        parent_ok = writable
      end
      (key = candidate) && break if ok
    end
  end
  ActiveStorage::Blob.create_and_upload!(io: File.open(path), filename: filename, content_type: content_type, key: key)
end

# A blob whose file never reached disk (an earlier run that crashed mid-upload)
# makes the API serve a URL that 500s. Drop this seed's own dangling ones first,
# so the attach steps below put them back.
ActiveStorage::Blob.where("filename LIKE 'qa-%'").find_each do |blob|
  next if blob.service.exist?(blob.key)

  blob.attachments.each(&:purge)
  blob.purge if ActiveStorage::Blob.exists?(blob.id)
end

# =============================================================================
puts "=== QA Seed: LOC-1 users ==="
# =============================================================================

loc_own = {
  kabul:     qa_user(email: "loc.kabul@hatiwal.test",     firstname: "Wahid",  lastname: "Kabuli",    place: :kabul),
  herat:     qa_user(email: "loc.herat@hatiwal.test",     firstname: "Nasrin", lastname: "Herawi",    place: :herat),
  mazar:     qa_user(email: "loc.mazar@hatiwal.test",     firstname: "Rahim",  lastname: "Balkhi",    place: :mazar),
  jalalabad: qa_user(email: "loc.jalalabad@hatiwal.test", firstname: "Gul",    lastname: "Nangarhari", place: :jalalabad),
  kandahar:  qa_user(email: "loc.kandahar@hatiwal.test",  firstname: "Asad",   lastname: "Kandahari", place: :kandahar)
}
# Own address abroad: the Bazaar must say "near Kabul", not Dubai.
loc_abroad = qa_user(email: "loc.abroad@hatiwal.test", firstname: "Farid", lastname: "Musafir", place: :dubai)
# Nothing at all: own address empty, no guess -> Kabul (source "default").
loc_none = qa_user(email: "loc.none@hatiwal.test", firstname: "Sima", lastname: "Khali")
# Saved language "ur" (Urdu is HIDDEN, owner 2026-10-05): the app must open in
# English for them, and Edit profile must still save.
qa_user(email: "lang.ur@hatiwal.test", firstname: "Imran", lastname: "Urdu", place: :kabul, language: "ur")
# A Pashto-language user with an own address, for the ps RTL flows.
loc_ps = qa_user(email: "loc.ps@hatiwal.test", firstname: "Zarghuna", lastname: "Pashtun", place: :jalalabad, language: "ps")

guess_users = [
  # [email, firstname, lastname, place, source, how long ago]
  [ "loc.guess.listing@hatiwal.test", "Hamid",  "Listing", :herat,     "listing",     2.days ],
  [ "loc.guess.search@hatiwal.test",  "Laila",  "Search",  :mazar,     "search_area", 5.hours ],
  [ "loc.guess.gps@hatiwal.test",     "Karim",  "Gps",     :jalalabad, "gps",         30.minutes ]
].map do |email, first, last, place, source, ago|
  [ qa_user(email: email, firstname: first, lastname: last), place, source, ago ]
end


# =============================================================================
puts "=== QA Seed: LOC-1 listings across provinces ==="
# =============================================================================

QA_LISTINGS = {
  kabul:     [ [ "Kabul QA — Toyota Corolla 2012", 650_000, "vehicles" ], [ "Kabul QA — Office desk", 4_500, "home" ], [ "Kabul QA — Samsung A54", 18_000, "electronics" ] ],
  herat:     [ [ "Herat QA — Handwoven carpet 2x3 m", 38_000, "home" ], [ "Herat QA — Saffron 100 g", 9_000, "food" ], [ "Herat QA — Bicycle 26 inch", 6_500, "sports" ] ],
  mazar:     [ [ "Mazar QA — Lapis lazuli necklace", 12_000, "gemstones" ], [ "Mazar QA — Winter coat", 2_800, "clothes" ], [ "Mazar QA — Dell laptop i5", 27_000, "electronics" ] ],
  jalalabad: [ [ "Jalalabad QA — Fresh oranges 10 kg", 900, "food" ], [ "Jalalabad QA — Honda 125 motorbike", 85_000, "vehicles" ], [ "Jalalabad QA — Kids bicycle", 3_200, "kids" ] ],
  kandahar:  [ [ "Kandahar QA — Pomegranates crate", 1_500, "food" ], [ "Kandahar QA — Embroidered dress", 4_000, "clothes" ], [ "Kandahar QA — Generator 5 kVA", 42_000, "tools" ] ]
}.freeze

fallback_category = Category.order(:position).first || abort("qa_features needs categories: run `bin/rails db:seed` first")
loc_listing_count = 0
QA_LISTINGS.each do |place, items|
  seller = loc_own.fetch(place)
  centre = QA_PLACES.fetch(place)
  items.each_with_index do |(title, price, slug), i|
    # Spread a little around the centre so "nearest first" has distances to sort.
    lat = centre[:latitude] + (i * 0.02)
    lng = centre[:longitude] + (i * 0.02)
    listing = Listing.find_or_initialize_by(user: seller, title: title)
    listing.assign_attributes(
      category: Category.find_by(slug: slug) || fallback_category,
      description: "QA seed listing in #{centre[:city]} for the \"items near you\" order.",
      price: price, currency: "AFN", location: "#{centre[:city]}, #{centre[:province]}",
      latitude: lat, longitude: lng, quantity: 1
    )
    listing.save! if listing.new_record? || listing.changed?
    # Back to live whatever flows did to it.
    listing.update_columns(status: Listing.statuses[:active], published_at: listing.published_at || (i + 1).days.ago,
                           reserved_at: nil, sold_at: nil, sold_units: 0, expires_at: nil, removed_at: nil)
    if !listing.images.attached? && File.exist?(QA_PHOTO)
      listing.images.attach(qa_blob(QA_PHOTO, "qa-loc-#{listing.id}.jpg", "image/jpeg"))
    end
    loc_listing_count += 1
  end
end
puts "  #{loc_listing_count} live listings across #{QA_LISTINGS.size} provinces (sellers: loc.<province>@)"

# Guesses are set AFTER the listings, so nothing a listing save records can
# leave a seller with a guess the seed did not ask for.
if qa_column?(User, :guessed_latitude)
  guess_users.each do |user, place, source, ago|
    p = QA_PLACES.fetch(place)
    user.update_columns(guessed_latitude: p[:latitude], guessed_longitude: p[:longitude],
                        guessed_province: p[:province], guessed_source: source, guessed_at: ago.ago)
  end
  # Everyone else starts with no guess, so "own > guess > default" is what the seed says.
  others = loc_own.values + [ loc_abroad, loc_none, loc_ps ]
  User.where(id: others.map(&:id))
      .update_all(guessed_latitude: nil, guessed_longitude: nil, guessed_province: nil, guessed_source: nil, guessed_at: nil)
  # One user with BOTH: own Kabul, a newer guess in Herat. Must still show Kabul.
  loc_own[:kabul].update_columns(guessed_latitude: QA_PLACES[:herat][:latitude], guessed_longitude: QA_PLACES[:herat][:longitude],
                                 guessed_province: "Herat", guessed_source: "listing", guessed_at: 1.hour.ago)
  puts "  guessed locations set (listing / search_area / gps) + loc.kabul has own Kabul AND a Herat guess"
else
  puts "  SKIP guessed locations: users.guessed_* not migrated yet (LOC-1)"
end

# =============================================================================
puts "=== QA Seed: VER-1 verification requests ==="
# =============================================================================

if defined?(VerificationRequest) && VerificationRequest.table_exists?
  admin = AdminUser.order(:id).first
  puts "  NOTE: no AdminUser yet — decided requests have no decided_by" unless admin

  sample = ->(name) { qa_blob(QA_SAMPLES.join("#{name}.png"), "qa-sample-#{name}.png", "image/png") }

  # Puts one user's request into an exact state. Rows are written directly: the
  # model's approve!/reject!/revoke! send Support messages, which seeds must not.
  # FAKE document numbers only (owner, 2026-10-05): all zeros + the user id, so
  # they are unique per account and obviously not anyone's real ID. Pass
  # `number:` to force one (the duplicate pair below).
  fake_number = ->(user) { "00000000#{format('%04d', user.id % 10_000)}" }
  full_number = VerificationRequest.column_names.include?("document_number")

  ver_fixture = lambda do |user, status:, document_type: "tazkira", reason_code: nil, reason_text: nil, number: nil,
                                 decided_ago: nil, files: true, purged: false, verified: false|
    VerificationRequest.where(subject: user).where.not(status: status).destroy_all
    request = VerificationRequest.find_or_initialize_by(subject: user, status: status)
    request.assign_attributes(
      requested_by: user, document_type: document_type,
      name_on_document: user.full_name,
      **(full_number ? { document_number: number || fake_number.call(user) } : { document_last4: "0000" }),
      reason_code: reason_code, reason_text: reason_text,
      decided_by: (admin if decided_ago), decided_at: decided_ago&.ago,
      checklist: decided_ago ? VerificationRequest::CHECKLIST.index_with { status == "approved" } : {},
      files_purged_at: (decided_ago.ago + VerificationRequest::FILES_KEPT_FOR if purged)
    )
    if files && !purged
      request.front.attach(sample.call("document_front")) unless request.front.attached?
      request.back.attach(sample.call("document_back")) if request.two_sided? && !request.back.attached?
      request.selfie.attach(sample.call("selfie")) unless request.selfie.attached?
    end
    user.update_column(:verified, false) # an open request needs an unverified subject
    request.save!
    request.update_columns(created_at: ((decided_ago || 0.days) + 1.day).ago)
    user.update_column(:verified, verified)
    request
  end

  # Eligible, never applied: the happy-path "Get verified" flow starts here.
  ver_none = qa_user(email: "ver.none@hatiwal.test", firstname: "Nadia", lastname: "Ready", place: :kabul, avatar: true)
  VerificationRequest.where(subject: ver_none).destroy_all
  ver_none.update_column(:verified, false)
  # Not eligible: no profile photo. The card must say what is missing.
  ver_noavatar = qa_user(email: "ver.noavatar@hatiwal.test", firstname: "Omid", lastname: "Nophoto", place: :herat)
  VerificationRequest.where(subject: ver_noavatar).destroy_all

  waiting = [
    [ "ver.requested@hatiwal.test",    "Bilal",  "Waiting",   "tazkira" ],
    [ "ver.requested2@hatiwal.test",   "Mina",   "Twosided",  "e_tazkira" ],
    [ "ver.requested.ps@hatiwal.test", "Shabnam", "Pashto",   "cnic" ]
  ]
  waiting.each do |email, first, last, doc|
    lang = email.include?(".ps@") ? "ps" : "en"
    u = qa_user(email: email, firstname: first, lastname: last, place: :kabul, avatar: true, language: lang)
    ver_fixture.call(u, status: "requested", document_type: doc)
  end

  approved = qa_user(email: "ver.approved@hatiwal.test", firstname: "Yusuf", lastname: "Verified", place: :mazar, avatar: true)
  ver_fixture.call(approved, status: "approved", decided_ago: 3.days, verified: true)
  # DUPLICATE pair: ver.requested2's waiting request carries ver.approved's number,
  # so the admin card must show the same-ID warning (#verify-same-number).
  if full_number
    dup = VerificationRequest.requested.find_by(subject: User.find_by(email: "ver.requested2@hatiwal.test"))
    dup&.update!(document_number: fake_number.call(approved))
  end

  user_reject_reasons = VerificationRequest::REJECT_REASONS - %w[shop_sign_not_visible] # that one is for shops (SHOP-1)
  user_reject_reasons.each do |code|
    u = qa_user(email: "ver.rejected.#{code.tr('_', '-')}@hatiwal.test", firstname: "Rejected",
                lastname: code.split("_").map(&:capitalize).join, place: :kandahar, avatar: true)
    ver_fixture.call(u, status: "rejected", reason_code: code, decided_ago: 1.day,
                        reason_text: ("QA: the photo shows a different document type." if code == "other"))
  end

  VerificationRequest::REVOKE_REASONS.each do |code|
    u = qa_user(email: "ver.revoked.#{code.tr('_', '-')}@hatiwal.test", firstname: "Revoked",
                lastname: code.split("_").map(&:capitalize).join, place: :jalalabad, avatar: true)
    ver_fixture.call(u, status: "revoked", reason_code: code, decided_ago: 2.days,
                        reason_text: ("QA: account shared with another person." if code == "other"))
  end

  cancelled = qa_user(email: "ver.cancelled@hatiwal.test", firstname: "Tamim", lastname: "Cancelled", place: :herat, avatar: true)
  ver_fixture.call(cancelled, status: "cancelled", decided_ago: 4.hours, files: false)

  # Decided 100 days ago: the purge job has already run, no photos left.
  purged = qa_user(email: "ver.purged@hatiwal.test", firstname: "Old", lastname: "Purged", place: :kabul, avatar: true)
  ver_fixture.call(purged, status: "rejected", reason_code: "photo_not_clear", decided_ago: 100.days, purged: true)

  counts = VerificationRequest.joins("JOIN users ON users.id = verification_requests.subject_id AND verification_requests.subject_type = 'User'")
                              .where("users.email LIKE 'ver.%@hatiwal.test'").group(:status).count
  puts "  requests by status: #{counts.sort.map { |s, n| "#{s}=#{n}" }.join(' ')}"
else
  puts "  SKIP verification requests: verification_requests table not migrated yet (VER-1)"
end

# =============================================================================
puts "=== QA Seed: SHOP-1 shops ==="
# =============================================================================
# Contract: hatiwal-mobile/qa/api_contract/SHOPS_2026-10.md. Status, verified_at
# and active_shop_id are written as columns: the model and admin paths may queue
# Support notices (shop_verified…), which seeds must never send.

if defined?(Shop) && Shop.table_exists?
  shop_cat = ->(slug) { Category.find_by(slug: slug) || fallback_category }
  sat_to_thu = %w[sat sun mon tue wed thu].index_with { [ %w[08:00 18:00] ] }.merge("fri" => [])

  qa_shop = lambda do |owner, name:, place:, slug:, hours: {}, status: "active", verified: false, phone: nil|
    p = QA_PLACES.fetch(place)
    shop = Shop.find_or_initialize_by(owner: owner)
    shop.assign_attributes(name: name, category: shop_cat.call(slug), latitude: p[:latitude], longitude: p[:longitude],
                           province: p[:province], city: p[:city], address_line: "#{p[:city]} QA bazaar, shop 7",
                           description: "QA seed shop.", hours: hours, phone: phone, phone_public: phone.present?)
    shop.save!
    shop.update_columns(status: Shop.statuses[status], verified_at: (verified ? 3.days.ago : nil), updated_at: Time.current)
    shop.logo.attach(qa_blob(QA_SAMPLES.join("avatar.png"), "qa-shop-logo-#{shop.id}.png", "image/png")) unless shop.logo.attached?
    shop
  end

  qa_shop_listing = lambda do |user, shop, title, price, slug, place|
    p = QA_PLACES.fetch(place)
    l = Listing.find_or_initialize_by(user: user, title: title)
    l.assign_attributes(category: shop_cat.call(slug), description: "QA seed listing.", price: price, currency: "AFN",
                        location: "#{p[:city]}, #{p[:province]}", latitude: p[:latitude], longitude: p[:longitude], quantity: 1)
    l.save! if l.new_record? || l.changed?
    l.update_columns(shop_id: shop&.id, status: Listing.statuses[:active], published_at: l.published_at || 1.day.ago,
                     reserved_at: nil, sold_at: nil, sold_units: 0, expires_at: nil, removed_at: nil)
    l.images.attach(qa_blob(QA_PHOTO, "qa-shop-#{l.id}.jpg", "image/jpeg")) if !l.images.attached? && File.exist?(QA_PHOTO)
    l
  end

  # No shop at all: every shop surface must look exactly like before SHOP-1.
  shop_none = qa_user(email: "shop.none@hatiwal.test", firstname: "Basir", lastname: "Noshop", place: :kabul, avatar: true)
  Shop.where(owner: shop_none).destroy_all
  # Opens a shop in maestro/shops/create_shop; the seed takes it away again.
  shop_new = qa_user(email: "shop.new@hatiwal.test", firstname: "Nazir", lastname: "Newshop", place: :kabul, avatar: true)
  shop_new.update_column(:active_shop_id, nil)
  Shop.where(owner: shop_new).find_each { |s| s.listings.update_all(shop_id: nil); s.destroy! }

  # Unverified shop, Sat–Thu 08–18, Friday closed; SELLING AS the shop.
  owner = qa_user(email: "shop.owner@hatiwal.test", firstname: "Umair", lastname: "Shopkeeper", place: :kabul, avatar: true)
  cosmetics = qa_shop.call(owner, name: "Kabul QA Cosmetics", place: :kabul, slug: "beauty", hours: sat_to_thu, phone: "+93700000111")
  # Mixed: 3 products in the shop, 2 personal listings of the same person.
  [ [ "Kabul QA Cosmetics — Lipstick set", 900, "beauty" ], [ "Kabul QA Cosmetics — Perfume 50 ml", 2_500, "beauty" ],
    [ "Kabul QA Cosmetics — Face cream", 700, "beauty" ] ].each { |t, pr, sl| qa_shop_listing.call(owner, cosmetics, t, pr, sl, :kabul) }
  [ [ "Umair personal QA — Old phone", 3_000, "electronics" ], [ "Umair personal QA — Chair", 1_200, "home" ] ]
    .each { |t, pr, sl| qa_shop_listing.call(owner, nil, t, pr, sl, :kabul) }
  owner.update_column(:active_shop_id, cosmetics.id)

  # Verified shop in Herat; selling as ME (active_shop_id unset).
  vowner = qa_user(email: "shop.verified@hatiwal.test", firstname: "Zahra", lastname: "Verifiedshop", place: :herat, avatar: true)
  carpets = qa_shop.call(vowner, name: "Herat QA Carpets", place: :herat, slug: "home",
                         hours: Shop::DAYS.index_with { [ %w[09:00 12:00], %w[14:00 19:00] ] }, verified: true)
  [ [ "Herat QA Carpets — Silk rug 2x3", 85_000, "home" ], [ "Herat QA Carpets — Kilim runner", 14_000, "home" ] ]
    .each { |t, pr, sl| qa_shop_listing.call(vowner, carpets, t, pr, sl, :herat) }
  vowner.update_column(:active_shop_id, nil)

  # Suspended shop whose owner still has it as active_shop_id: a STALE choice,
  # so `selling_as_shop` must come back null and the shop must not be public.
  sowner = qa_user(email: "shop.suspended@hatiwal.test", firstname: "Jawid", lastname: "Suspended", place: :mazar, avatar: true)
  phones = qa_shop.call(sowner, name: "Mazar QA Phones", place: :mazar, slug: "electronics", status: "suspended")
  qa_shop_listing.call(sowner, phones, "Mazar QA Phones — Charger", 400, "electronics", :mazar)
  sowner.update_column(:active_shop_id, phones.id)

  # Shop verification (VER-1 for shops): Cosmetics waiting, Carpets approved.
  # Same rule as the user fixtures: rows written directly, no approve!.
  if VerificationRequest::SUBJECT_TYPES.include?(Shop.name)
    { cosmetics => [ "requested", nil ], carpets => [ "approved", 3.days ] }.each do |shop, (status, ago)|
      VerificationRequest.where(subject: shop).where.not(status: status).destroy_all
      r = VerificationRequest.find_or_initialize_by(subject: shop, status: status)
      r.assign_attributes(requested_by: shop.owner, document_type: "licence", phone: "+93700000222",
                          decided_at: ago&.ago, decided_by: (AdminUser.order(:id).first if ago),
                          checklist: ago ? VerificationRequest::SHOP_CHECKLIST.index_with { true } : {})
      r.front.attach(qa_blob(QA_SAMPLES.join("shop_front.png"), "qa-sample-shop-front.png", "image/png")) unless r.front.attached?
      r.back.attach(qa_blob(QA_SAMPLES.join("document_front.png"), "qa-sample-licence.png", "image/png")) unless r.back.attached?
      r.save!
    end
    puts "  shop verification: Kabul QA Cosmetics requested, Herat QA Carpets approved"
  end
  puts "  shops: #{[ cosmetics, carpets, phones ].map { |s| "#{s.name} (#{s.status}#{', verified' if s.verified_at})" }.join(' · ')}"
  puts "  shop.owner sells as the shop; shop.verified as Me; shop.suspended has a stale active shop; shop.none has none"
else
  puts "  SKIP shops: shops table not migrated yet (SHOP-1)"
end

# =============================================================================
puts "=== QA Seed: check — no Support threads ==="
# =============================================================================

qa_ids = User.where("email LIKE 'loc.%@hatiwal.test' OR email LIKE 'ver.%@hatiwal.test' OR email LIKE 'shop.%@hatiwal.test' OR email LIKE 'lang.%@hatiwal.test'").pluck(:id)
threads = Conversation.where(buyer_id: qa_ids).or(Conversation.where(seller_id: qa_ids)).count
abort "  FAIL: #{threads} conversation(s) involve QA feature users — seeds must create none" if threads.positive?
puts "  ok — #{qa_ids.size} QA feature users, 0 conversations"
