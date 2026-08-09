class CategorySerializer < ApplicationSerializer
  fields :id, :slug, :icon, :position

  field(:name_en) { |c| c.name_en }
  field(:name_ps) { |c| c.name_ps }
  field(:name_fa) { |c| c.name_fa }

  view :with_subcategories do
    field(:subcategories) do |c|
      CategorySerializer.render_as_hash(c.visible_subcategories, view: :default)
    end
  end

  # Leaf view for the subcategories nested under a hub card: its own count and
  # nothing else, so rendering children costs no extra query.
  view :with_count do
    field(:active_listings_count) do |c, opts|
      (opts[:counts_by_id] || {})[c.id].to_i
    end
  end

  # Category hub view. Every row — parent and subcategory alike — carries an
  # active_listings_count, so a client can show buyers where the inventory
  # actually is without a request per row. All counts are precomputed in the
  # controller in a single GROUP BY and passed in via opts[:counts_by_id]; a
  # parent's count rolls up its subcategories' (see the controller for why).
  view :with_counts do
    include_view :with_count

    field(:subcategories) do |c, opts|
      CategorySerializer.render_as_hash(
        c.visible_subcategories,
        view: :with_count,
        counts_by_id: opts[:counts_by_id]
      )
    end
  end
end
