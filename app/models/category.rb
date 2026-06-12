class Category < ApplicationRecord
  has_many :listings, dependent: :restrict_with_error

  validates :name_en, presence: true
  validates :name_ps, presence: true
  validates :name_fa, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active,   -> { where(active: true) }
  scope :ordered,  -> { order(:position) }

  def name_for(locale)
    case locale.to_s
    when "ps" then name_ps
    when "fa" then name_fa
    else name_en
    end
  end
end
