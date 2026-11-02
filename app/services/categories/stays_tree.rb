module Categories
  # The Stays category tree (docs/STAYS_DESIGN.md §2.1), kept in one place for
  # the data migrations, the seeds and the specs. Idempotent: run it again and
  # nothing changes. ps/fa/ur wording awaits the owner's review.
  #
  # Two separate steps, so the owner's open question (§2.1) is a one-line switch:
  #   apply!               the Stays root + its own subcategories   (always)
  #   move_guest_houses!   Property › Guest Houses → Stays (same row) (option A, default)
  #   restore_guest_houses! the reverse                               (option B / rollback)
  module StaysTree
    GUEST_HOUSES = "guest-houses".freeze
    PROPERTY = "property".freeze

    ROOT = {
      slug: "stays", icon: "🛏️",
      name_en: "Stays", name_ps: "استوګنځایونه", name_fa: "اقامتگاه", name_ur: "قیام گاہیں"
    }.freeze

    CHILDREN = [
      { slug: "hotel-rooms", icon: "🏨", position: 1,
        name_en: "Hotel Rooms", name_ps: "د هوټل کوټې", name_fa: "اتاق هتل", name_ur: "ہوٹل کے کمرے" },
      { slug: "bed-breakfast", icon: "🍳", position: 3,
        name_en: "Bed & Breakfast", name_ps: "کوټه او سهارنی", name_fa: "اتاق با صبحانه", name_ur: "بستر اور ناشتہ" },
      { slug: "short-stay-apartments", icon: "🏢", position: 4,
        name_en: "Short-stay Apartments", name_ps: "لنډمهاله اپارتمانونه", name_fa: "آپارتمان کوتاه‌مدت", name_ur: "مختصر قیام اپارٹمنٹس" }
    ].freeze

    # Only used when the row does not exist yet (a fresh database).
    GUEST_HOUSES_ATTRS = {
      slug: GUEST_HOUSES, icon: "🛏️", position: 2,
      name_en: "Guest Houses", name_ps: "مېلمستونونه", name_fa: "مهمان‌خانه و مسافرخانه", name_ur: "گیسٹ ہاؤس"
    }.freeze

    module_function

    # The Stays root and its own subcategories, kind "stay". Never moves anything.
    def apply!
      done = { created: [], kind_set: [] }
      Category.transaction do
        root = Category.find_or_initialize_by(slug: ROOT[:slug])
        if root.new_record?
          done[:created] << root.slug
          property = Category.find_by(slug: PROPERTY, parent_id: nil)
          root.assign_attributes(ROOT.merge(position: property ? property.position + 1 : Category.top_level.maximum(:position).to_i + 1))
        end
        root.kind = Category::KIND_STAY
        root.save!

        CHILDREN.each do |attrs|
          child = Category.find_or_initialize_by(slug: attrs[:slug])
          if child.new_record?
            child.assign_attributes(attrs)
            done[:created] << child.slug
          elsif child.kind != Category::KIND_STAY
            done[:kind_set] << child.slug
          end
          child.parent = root
          child.save!
        end
      end
      done
    end

    # Option A (default): Property › Guest Houses moves under Stays — the same
    # row, so its listings follow. Creates it there on a fresh database.
    def move_guest_houses!
      apply! # the root must exist first, whatever order this runs in
      root = Category.find_by!(slug: ROOT[:slug])
      guest = Category.find_or_initialize_by(slug: GUEST_HOUSES)
      created = guest.new_record?
      guest.assign_attributes(GUEST_HOUSES_ATTRS) if created
      moved = !created && guest.parent_id != root.id
      guest.parent = root
      guest.save!
      { created: created, moved: moved }
    end

    # Option B / rollback: Guest Houses back under Property, an item again.
    def restore_guest_houses!
      guest = Category.find_by(slug: GUEST_HOUSES)
      property = Category.find_by(slug: PROPERTY, parent_id: nil)
      return { restored: false } unless guest && property

      guest.update!(parent: property)
      guest.update!(kind: Category::KIND_ITEM) if guest.reload.kind != Category::KIND_ITEM
      { restored: true }
    end

    # Rollback of apply!: removes the Stays categories that hold no listing
    # (a listing keeps its category: those stay, and the rollback says so).
    def remove!
      slugs = CHILDREN.map { |c| c[:slug] } + [ ROOT[:slug] ]
      kept = []
      Category.where(slug: slugs).order(Arel.sql("parent_id IS NULL")).each do |cat|
        if cat.listings.exists? || cat.subcategories.exists?
          kept << cat.slug
        else
          cat.destroy!
        end
      end
      { kept: kept }
    end
  end
end
