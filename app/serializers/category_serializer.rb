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
end
