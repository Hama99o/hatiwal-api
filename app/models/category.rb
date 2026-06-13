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

  def name_for(locale)
    case locale.to_s
    when "ps" then name_ps
    when "fa" then name_fa
    else name_en
    end
  end
end
