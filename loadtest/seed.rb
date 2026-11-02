# Load-test volume (docs/LOAD_TEST.md): users, listings with photos,
# conversations and messages, inserted in bulk into the LOAD-TEST database only.
# Run by loadtest/run.sh seed (bin/rails runner inside the production image).
#
# Sizes from the environment (defaults = the planned run):
#   LT_USERS=2000 LT_LISTINGS=5000 LT_CONVERSATIONS=4000 LT_MESSAGES=20000
#   LT_BLOBS=300 (distinct photo blobs, so thumb generation is per blob, not
#   one cached file) LT_TOKEN_USERS=600 (users k6 signs requests as)
#
# Bulk inserts skip validations and callbacks on purpose (speed); every column
# a read path needs is set here explicitly. It also writes, for k6:
#   /loadtest-tokens/tokens.json   auth headers per user (no sign-in during the
#                                  test: sign_in is throttled to 20 / 5 min / IP)
#   /loadtest-tokens/meta.json     listing ids, category ids, search words
db = ActiveRecord::Base.connection_db_config
abort "refusing: LOADTEST is not set" unless ENV["LOADTEST"] == "1"
abort "refusing: database host is #{db.host.inspect}, not loadtest-db" unless db.host == "loadtest-db"
puts "DB: #{db.host}/#{ActiveRecord::Base.connection.current_database} (env #{Rails.env})"

require "securerandom"
srand(20_261_009) # same data every run

n_users = Integer(ENV.fetch("LT_USERS", 2000))
n_listings = Integer(ENV.fetch("LT_LISTINGS", 5000))
n_convos = Integer(ENV.fetch("LT_CONVERSATIONS", 4000))
n_messages = Integer(ENV.fetch("LT_MESSAGES", 20_000))
n_blobs = Integer(ENV.fetch("LT_BLOBS", 300))
n_token_users = [ Integer(ENV.fetch("LT_TOKEN_USERS", 600)), n_users ].min
password = "Loadtest123!"
now = Time.current
out = Pathname("/loadtest-tokens")

if User.where("email LIKE 'lt+%@loadtest.invalid'").exists?
  abort "already seeded (lt+…@loadtest.invalid users exist): `loadtest/run.sh reset` first"
end

PLACES = [
  [ "Kabul", "Kabul", 34.5553, 69.2075 ], [ "Herat", "Herat", 34.3529, 62.2040 ],
  [ "Mazar-i-Sharif", "Balkh", 36.7090, 67.1109 ], [ "Kandahar", "Kandahar", 31.6133, 65.7101 ],
  [ "Jalalabad", "Nangarhar", 34.4265, 70.4515 ], [ "Peshawar", "Khyber Pakhtunkhwa", 34.0151, 71.5249 ],
  [ "Islamabad", "Islamabad", 33.6844, 73.0479 ], [ "Lahore", "Punjab", 31.5204, 74.3587 ]
].freeze
WORDS = {
  "vehicles" => %w[Toyota Corolla Suzuki Honda motorbike Land Cruiser bicycle],
  "electronics" => %w[Samsung iPhone laptop ThinkPad camera speaker tablet charger],
  "clothes" => %w[jacket coat shoes sneakers dress shawl perahan],
  "home" => %w[sofa armchair carpet wardrobe table fridge stove],
  "books" => %w[textbook Quran dictionary novel],
  "food" => %w[saffron honey pomegranate almonds raisins]
}.freeze
jitter = ->(v) { (v + rand(-0.05..0.05)).round(6) }

# ── Users ──────────────────────────────────────────────────────────────────
digest = Devise::Encryptor.digest(User, password)
user_rows = (1..n_users).map do |i|
  city, province, lat, lng = PLACES[i % PLACES.size]
  email = "lt+#{i}@loadtest.invalid"
  { email: email, uid: email, provider: "email", encrypted_password: digest, firstname: "Load",
    lastname: "User #{i}", city: city, province: province, latitude: jitter.(lat), longitude: jitter.(lng),
    confirmed_at: now, seller_mode: true, preferred_language: %w[en ps fa][i % 3],
    created_at: now - rand(1..300).days, updated_at: now }
end
user_ids = user_rows.each_slice(1000).flat_map { |s| User.insert_all!(s, returning: :id).rows.flatten }
puts "users: #{user_ids.size}"

# ── Photo blobs (distinct keys: each needs its own thumb / medium generation) ─
files = Dir[Rails.root.join("db/seeds/images/*/*.jpg").to_s].sort
abort "no seed photos in db/seeds/images" if files.empty?
blob_ids = Array.new(n_blobs) do |i|
  path = files[i % files.size]
  blob = ActiveStorage::Blob.create_and_upload!(io: File.open(path), filename: "lt-#{i}-#{File.basename(path)}",
                                                content_type: "image/jpeg")
  blob.analyze # width/height: PublicImageUrl only makes variants of analysed blobs
  blob.id
end
puts "photo blobs: #{blob_ids.size} (from #{files.size} seed photos)"

# ── Listings ───────────────────────────────────────────────────────────────
categories = Category.where(parent_id: nil).to_a
abort "no categories: db:seed must run first" if categories.empty?
statuses = Listing.statuses
listing_rows = (1..n_listings).map do |i|
  cat = categories.sample
  words = WORDS.fetch(cat.slug, %w[item goods used new])
  city, province, lat, lng = PLACES.sample
  status = case rand(100) when 0...85 then :active when 85...90 then :reserved when 90...95 then :sold else :draft end
  published = status == :draft ? nil : now - rand(0..29).days
  { user_id: user_ids.sample, category_id: cat.id, title: "#{words.sample(2).join(' ')} #{i}",
    description: "Load-test listing #{i}. #{words.sample(4).join(', ')}. Good condition, #{city}.",
    price: rand(500..900_000), currency: %w[AFN AFN AFN PKR][i % 4], status: statuses.fetch(status.to_s),
    location: "#{city}, #{province}", latitude: jitter.(lat), longitude: jitter.(lng),
    published_at: published, expires_at: published && published + 60.days,
    sold_at: status == :sold ? now - 1.day : nil, reserved_at: status == :reserved ? now - 1.day : nil,
    views_count: rand(0..500), bumped_at: published || now, created_at: published || now, updated_at: now }
end
listing_ids = listing_rows.each_slice(1000).flat_map { |s| Listing.insert_all!(s, returning: :id).rows.flatten }
puts "listings: #{listing_ids.size}"

attachment_rows = listing_ids.flat_map do |id|
  blob_ids.sample(rand(1..3)).map { |b| { name: "images", record_type: "Listing", record_id: id, blob_id: b, created_at: now } }
end
attachment_rows.each_slice(5000) { |s| ActiveStorage::Attachment.insert_all!(s) }
puts "listing photos: #{attachment_rows.size} attachments over #{blob_ids.size} blobs"

# ── Conversations + messages ───────────────────────────────────────────────
live = Listing.where(id: listing_ids, status: [ statuses["active"], statuses["reserved"] ]).pluck(:id, :user_id)
pairs = {}
while pairs.size < n_convos
  listing_id, seller_id = live.sample
  buyer_id = user_ids.sample
  next if buyer_id == seller_id

  pairs[[ listing_id, buyer_id ]] ||= seller_id
end
convo_rows = pairs.map do |(listing_id, buyer_id), seller_id|
  { listing_id: listing_id, buyer_id: buyer_id, seller_id: seller_id, created_at: now - rand(1..20).days, updated_at: now }
end
convos = convo_rows.each_slice(1000).flat_map do |s|
  Conversation.insert_all!(s, returning: %i[id buyer_id seller_id]).rows
end
puts "conversations: #{convos.size}"

message_rows = Array.new(n_messages) do |i|
  id, buyer, seller = convos.sample
  at = now - rand(1..400_000).seconds
  { conversation_id: id, user_id: i.even? ? buyer : seller, body: "Load-test message #{i}: is it still available?",
    created_at: at, updated_at: at, read_at: rand < 0.7 ? at + 60 : nil }
end
message_rows.each_slice(5000) { |s| Message.insert_all!(s) }
ActiveRecord::Base.connection.execute(<<~SQL)
  UPDATE conversations c SET last_message_at = m.last
  FROM (SELECT conversation_id, MAX(created_at) AS last FROM messages GROUP BY conversation_id) m
  WHERE m.conversation_id = c.id AND c.id IN (#{convos.map(&:first).join(',')})
SQL
puts "messages: #{message_rows.size}"

# ── For k6 ────────────────────────────────────────────────────────────────
out.mkpath
tokens = User.where(id: user_ids.first(n_token_users)).order(:id).map do |u|
  h = u.create_new_auth_token # one device token each; nothing signs in during the test
  u.save!
  { "access-token" => h["access-token"], "client" => h["client"], "uid" => h["uid"], "token-type" => "Bearer" }
end
out.join("tokens.json").write(JSON.generate(tokens))
browsable = Listing.where(id: listing_ids).browsable.pluck(:id)
out.join("meta.json").write(JSON.generate(
  listing_ids: browsable, category_ids: categories.map(&:id),
  search_words: WORDS.values.flatten.uniq, places: PLACES.map { |p| { lat: p[2], lng: p[3] } }
))
puts "k6: #{tokens.size} user tokens, #{browsable.size} browsable listing ids → #{out}"
