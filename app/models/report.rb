class Report < ApplicationRecord
  belongs_to :reporter, class_name: User.name, foreign_key: :reporter_id
  belongs_to :reportable, polymorphic: true

  enum :reason, {
    spam: 0,
    inappropriate: 1,
    fraud: 2,
    wrong_category: 3,
    prohibited_item: 4,
    other: 5
  }

  enum :status, { pending: 0, reviewed: 1, resolved: 2, dismissed: 3 }

  validates :reason, presence: true
  validates :description, length: { maximum: 1000 }, allow_blank: true
  validates :reportable_id, uniqueness: {
    scope:   %i[reporter_id reportable_type],
    message: :already_reported
  }
  validate :not_reporting_own_content

  private

  def not_reporting_own_content
    if reportable.is_a?(Listing) && reportable.user_id == reporter_id
      errors.add(:base, "cannot report your own listing")
    end
    if reportable.is_a?(User) && reportable.id == reporter_id
      errors.add(:base, "cannot report yourself")
    end
  end
end
