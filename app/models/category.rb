class Category < ApplicationRecord
  belongs_to :parent, class_name: Category.name, optional: true
  has_many :subcategories,
           class_name: Category.name,
           foreign_key: :parent_id,
           dependent: :destroy,
           inverse_of: :parent
  has_many :listings, dependent: :restrict_with_error

  validates :name_en, presence: true
  validates :name_ps, presence: true
  validates :name_fa, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active,      -> { where(active: true) }
  scope :ordered,     -> { order(:position) }
  scope :top_level,   -> { where(parent_id: nil) }
  scope :children_of, ->(id) { where(parent_id: id) }
  # A category together with its direct children — the set that "this category"
  # actually means to a buyer. The create-listing picker lets a seller file an
  # item under a subcategory ("Electronics > Phones"), so any filter or count
  # for the parent has to reach into its children too.
  scope :self_and_children, ->(id) { where(id: id).or(where(parent_id: id)) }

  # Active children in position order, filtered in Ruby rather than through
  # `subcategories.active.ordered` so an eager-loaded `includes(:subcategories)`
  # is reused instead of firing one extra query per parent.
  def visible_subcategories
    subcategories.select(&:active?).sort_by { |c| [ c.position.to_i, c.id ] }
  end

  def name_for(locale)
    case locale.to_s
    when "ps" then name_ps
    when "fa" then name_fa
    else name_en
    end
  end
end
