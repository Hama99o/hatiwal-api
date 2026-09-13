# Add the "Gemstones & Minerals" tree WITHOUT touching anything else.
#
# WHY THIS EXISTS SEPARATELY FROM SEEDS: `db:seed` rebuilds the whole database.
# The local dev DB has real listings, conversations and QA fixtures on it, and
# the two QA emulators are driving against it continuously — a reseed would pull
# the rug out from under a running test campaign. Production obviously cannot be
# seeded either. This touches ONLY these categories.
#
# IDEMPOTENT: find_or_initialize_by(slug:), so re-running updates names in place
# and never duplicates a row.
#
# RUN IT (local):
#   docker compose exec -T web bin/rails runner "$(cat db/scripts/add_gemstone_categories.rb)"
# RUN IT (production) — base64 so the Urdu/Pashto text survives shell quoting:
#   B=$(base64 -w0 db/scripts/add_gemstone_categories.rb)
#   bin/kms runner "require \"base64\"; eval(Base64.decode64(\"$B\"))"

PARENT = {
  slug: "gemstones", name_en: "Gemstones & Minerals",
  name_ps: "قیمتي ډبرې او معدنیات", name_fa: "سنگ‌های قیمتی و معادن",
  name_ur: "قیمتی پتھر اور معدنیات", icon: "💎", position: 12
}.freeze

# Stones that actually matter in Afghanistan and Pakistan: Panjshir emerald,
# Jegdalek ruby, Badakhshan lapis, Nuristan tourmaline; Swat emerald and
# Gilgit-Baltistan aquamarine/topaz on the Pakistani side. Before this tree
# existed a seller had to file a lapis block under "Other".
CHILDREN = [
  { slug: "ruby",          name_en: "Ruby",              name_ps: "یاقوت",            name_fa: "یاقوت سرخ",        name_ur: "یاقوت",                   icon: "❤️",  position: 1 },
  { slug: "emerald",       name_en: "Emerald",           name_ps: "زمرد",             name_fa: "زمرد",             name_ur: "زمرد",                    icon: "💚",  position: 2 },
  { slug: "lapis-lazuli",  name_en: "Lapis Lazuli",      name_ps: "لاجورد",           name_fa: "لاجورد",           name_ur: "لاجورد",                  icon: "🔷",  position: 3 },
  { slug: "tourmaline",    name_en: "Tourmaline",        name_ps: "تورمالین",         name_fa: "تورمالین",         name_ur: "ٹورمالین",                icon: "🌈",  position: 4 },
  { slug: "sapphire",      name_en: "Sapphire",          name_ps: "نیلم",             name_fa: "یاقوت کبود",       name_ur: "نیلم",                    icon: "💠",  position: 5 },
  { slug: "turquoise",     name_en: "Turquoise",         name_ps: "فیروزه",           name_fa: "فیروزه",           name_ur: "فیروزہ",                  icon: "🩵",  position: 6 },
  { slug: "quartz",        name_en: "Quartz & Crystals", name_ps: "کوارتز او کرسټل",  name_fa: "کوارتز و کریستال", name_ur: "کوارٹز اور کرسٹل",        icon: "🔮",  position: 7 },
  { slug: "jade",          name_en: "Jade & Serpentine", name_ps: "یشم",              name_fa: "یشم",              name_ur: "یشب",                     icon: "🟢",  position: 8 },
  { slug: "rough-stone",   name_en: "Rough & Raw Stone", name_ps: "خام ډبره",         name_fa: "سنگ خام",          name_ur: "کچا پتھر",                icon: "🪨",  position: 9 },
  { slug: "gem-supplies",  name_en: "Gem Tools & Supplies", name_ps: "د ډبرو وسایل", name_fa: "ابزار سنگ",        name_ur: "پتھر تراشی کے اوزار",     icon: "🛠️", position: 10 }
].freeze

def upsert(attrs, parent_id: nil)
  c = Category.find_or_initialize_by(slug: attrs[:slug])
  created = c.new_record?
  c.name_en = attrs[:name_en]
  c.name_ps = attrs[:name_ps]
  c.name_fa = attrs[:name_fa]
  c.name_ur = attrs[:name_ur] if c.respond_to?(:name_ur=)
  c.icon = attrs[:icon]
  c.position = attrs[:position]
  c.parent_id = parent_id
  c.active = true if c.respond_to?(:active=)
  c.save!
  puts "  #{created ? 'created' : 'updated'} #{attrs[:slug]}"
  c
end

parent = upsert(PARENT)
CHILDREN.each { |a| upsert(a, parent_id: parent.id) }

puts "gemstones tree: #{Category.where(parent_id: parent.id).count} children"
puts "total categories: #{Category.count}"
