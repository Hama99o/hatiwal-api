class CategorySerializer < ApplicationSerializer
  fields :id, :slug, :icon, :position

  field(:name_en) { |c| c.name_en }
  field(:name_ps) { |c| c.name_ps }
  field(:name_fa) { |c| c.name_fa }

  view :with_subcategories do
    field(:subcategories) do |c|
      CategorySerializer.render_as_hash(c.subcategories.active.ordered, view: :default)
    end
  end

  # Adds active_listings_count for the category hub screen.
  # The count is precomputed in the controller via a single GROUP BY query and
  # passed in via opts[:counts_by_id] — no per-category SQL query is issued here.
  view :with_counts do
    field(:active_listings_count) do |c, opts|
      (opts[:counts_by_id] || {})[c.id].to_i
    end

    field(:subcategories) do |c|
      CategorySerializer.render_as_hash(c.subcategories.active.ordered, view: :default)
    end
  end
end
