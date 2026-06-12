class CategorySerializer < ApplicationSerializer
  fields :id, :slug, :icon, :position

  field(:name_en) { |c| c.name_en }
  field(:name_ps) { |c| c.name_ps }
  field(:name_fa) { |c| c.name_fa }
end
