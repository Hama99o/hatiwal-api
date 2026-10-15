module Categories
  # The Stays category tree (docs/STAYS_DESIGN.md §2.1), kept in one place for
  # the data migration, the seeds and the specs. Idempotent: run it again and
  # nothing changes. ps/fa/ur wording awaits the owner's review.
  module StaysTree
    ROOT = {
      slug: "stays", icon: "🛏️",
      name_en: "Stays", name_ps: "استوګنځایونه", name_fa: "اقامتگاه", name_ur: "قیام گاہیں"
    }.freeze

    CHILDREN = [
      { slug: "hotel-rooms", icon: "🏨", position: 1,
        name_en: "Hotel Rooms", name_ps: "د هوټل کوټې", name_fa: "اتاق هتل", name_ur: "ہوٹل کے کمرے" },
      { slug: "guest-houses", icon: "🛏️", position: 2,
        name_en: "Guest Houses", name_ps: "مېلمستونونه", name_fa: "مهمان‌خانه و مسافرخانه", name_ur: "گیسٹ ہاؤس" },
      { slug: "bed-breakfast", icon: "🍳", position: 3,
        name_en: "Bed & Breakfast", name_ps: "کوټه او سهارنی", name_fa: "اتاق با صبحانه", name_ur: "بستر اور ناشتہ" },
      { slug: "short-stay-apartments", icon: "🏢", position: 4,
        name_en: "Short-stay Apartments", name_ps: "لنډمهاله اپارتمانونه", name_fa: "آپارتمان کوتاه‌مدت", name_ur: "مختصر قیام اپارٹمنٹس" }
    ].freeze

    module_function

    # Returns what it did, e.g. { created: ["stays", …], moved: ["guest-houses"] }.
    def apply!
      done = { created: [], moved: [], kind_set: [] }
      Category.transaction do
        root = Category.find_or_initialize_by(slug: ROOT[:slug])
        done[:created] << root.slug if root.new_record?
        if root.new_record?
          property = Category.find_by(slug: "property", parent_id: nil)
          root.assign_attributes(ROOT.merge(position: property ? property.position + 1 : Category.top_level.maximum(:position).to_i + 1))
        end
        root.kind = Category::KIND_STAY
        root.save!

        CHILDREN.each do |attrs|
          child = Category.find_or_initialize_by(slug: attrs[:slug])
          if child.new_record?
            child.assign_attributes(attrs)
            done[:created] << child.slug
          elsif child.parent_id != root.id
            done[:moved] << child.slug
          end
          child.parent = root
          done[:kind_set] << child.slug if child.persisted? && child.kind != Category::KIND_STAY
          child.kind = Category::KIND_STAY
          child.save!
        end
      end
      done
    end
  end
end
