# Backfill Urdu (name_ur) for every category, and add the column if the deploy
# has not brought it yet.
#
# WHY THIS EXISTS AS A SCRIPT RATHER THAN A SEED RUN: seeds rebuild the whole
# database. Production already holds real listings, users and conversations, so
# `db:seed` there is not an option. This touches ONLY categories.name_ur.
#
# It is IDEMPOTENT — safe to run repeatedly. It adds the column only when absent,
# records the migration version only when absent, and writes names with
# update_column (no callbacks, no validations, no timestamps churn).
#
# RUN IT:
#   cd hatiwal-api
#   bin/kms runner "$(cat db/scripts/backfill_urdu_category_names.rb)"
#
# If the shell mangles the quoting (it contains Urdu text and #{} interpolation),
# use the base64 form instead, which is quote-proof:
#   B=$(base64 -w0 db/scripts/backfill_urdu_category_names.rb)
#   bin/kms runner "require \"base64\"; eval(Base64.decode64(\"$B\"))"
#
# AFTER A REAL DEPLOY this script is still safe: the column and the
# schema_migrations row will already exist, so it only refreshes the names.

conn = ActiveRecord::Base.connection

unless conn.column_exists?(:categories, :name_ur)
  conn.add_column :categories, :name_ur, :string
  puts "added categories.name_ur"
else
  puts "categories.name_ur already present"
end

# Matches db/migrate/20260913135727_add_name_ur_to_categories.rb. Recording it
# means a later `kamal deploy` skips that migration instead of failing on a
# duplicate column.
VERSION = "20260913135727"
if conn.select_value("SELECT 1 FROM schema_migrations WHERE version = '#{VERSION}'").nil?
  conn.execute("INSERT INTO schema_migrations (version) VALUES ('#{VERSION}')")
  puts "recorded migration #{VERSION}"
else
  puts "migration #{VERSION} already recorded"
end

UR = {
  # Top level
  "electronics" => "الیکٹرانکس", "clothes" => "کپڑے اور فیشن", "vehicles" => "گاڑیاں",
  "home" => "گھر اور فرنیچر", "books" => "کتابیں اور تعلیم", "food" => "خوراک اور زراعت",
  "tools" => "اوزار اور سامان", "sports" => "کھیل اور تفریح", "beauty" => "خوبصورتی اور صحت",
  "bags" => "بیگ اور لوازمات", "kids" => "بچے اور کھلونے", "property" => "جائیداد",
  "jobs" => "ملازمتیں", "services" => "خدمات", "other" => "دیگر",
  # Subcategories
  "phones" => "موبائل اور ٹیبلٹ", "computers" => "کمپیوٹر اور لیپ ٹاپ", "tv-audio" => "ٹی وی اور آڈیو",
  "cameras" => "کیمرے", "tech-accessories" => "لوازمات", "mens-clothing" => "مردانہ کپڑے",
  "womens-clothing" => "زنانہ کپڑے", "kids-clothing" => "بچوں کے کپڑے",
  "traditional-clothing" => "روایتی لباس", "shoes" => "جوتے", "cars" => "کاریں",
  "motorcycles" => "موٹر سائیکل", "bicycles" => "سائیکل", "vehicle-parts" => "پرزہ جات",
  "furniture" => "فرنیچر", "kitchen" => "باورچی خانہ اور آلات", "bedding" => "بستر اور پردے",
  "garden" => "باغ اور اوزار", "books-general" => "کتابیں", "school-supplies" => "اسکول کا سامان",
  "food-products" => "غذائی اشیاء", "agriculture" => "زراعت اور کاشتکاری",
  "livestock" => "جانور اور مویشی", "hand-tools" => "دستی اوزار", "power-tools" => "بجلی کے اوزار",
  "industrial" => "صنعتی سامان", "fitness" => "ورزش کا سامان", "cycling" => "سائیکلنگ",
  "outdoor-sports" => "بیرونی کھیل", "team-sports" => "ٹیم کھیل", "skincare" => "جلد کی دیکھ بھال",
  "haircare" => "بالوں کی دیکھ بھال", "fragrances" => "خوشبویات", "health" => "صحت اور طبی",
  "bags-purses" => "بیگ اور پرس", "watches" => "گھڑیاں", "jewelry" => "زیورات",
  "toys" => "کھلونے اور گیمز", "baby" => "بچوں کا سامان",
  # Gemstones & Minerals — added to production 2026-09-13
  "gemstones" => "قیمتی پتھر اور معدنیات", "lapis-lazuli" => "لاجورد", "ruby" => "یاقوت",
  "emerald" => "زمرد", "tourmaline" => "ٹورمالین", "kunzite" => "کنزائٹ",
  "aquamarine" => "ایکوامرین", "spinel" => "اسپنل", "sapphire" => "نیلم", "topaz" => "پکھراج",
  "peridot" => "زبرجد", "garnet" => "گارنیٹ", "amethyst" => "جامنی یاقوت", "turquoise" => "فیروزہ",
  "quartz" => "کوارٹز اور کرسٹل", "onyx-marble" => "سنگ سلیمانی اور سنگ مرمر", "jade" => "یشب",
  "rough-stone" => "کچا پتھر", "gem-supplies" => "پتھر تراشی کے اوزار"
}.freeze

Category.reset_column_information

updated = 0
missing = []
UR.each do |slug, name|
  category = Category.find_by(slug: slug)
  if category.nil?
    missing << slug
    next
  end
  category.update_column(:name_ur, name)
  updated += 1
end

puts "urdu names written: #{updated} of #{UR.size}"
puts "slugs not found: #{missing.inspect}" unless missing.empty?

without = Category.where(name_ur: [ nil, "" ]).pluck(:slug)
puts "categories STILL without urdu: #{without.size} #{without.first(8).inspect}"
puts "total categories: #{Category.count}"
