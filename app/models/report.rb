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
  }, validate: true # an unknown reason is a 422, not an ArgumentError 500 (night QA 2026-10-12)

  enum :status, { pending: 0, reviewed: 1, resolved: 2, dismissed: 3 }

  # privacy-b: a shop is reported by ITS id (a buyer's app never has the
  # owner's). Only these can be reported; anything else is refused rather than
  # constantized.
  REPORTABLE_TYPES = [ Listing.name, User.name, Shop.name ].freeze

  validates :reportable_type, inclusion: { in: REPORTABLE_TYPES }
  validates :reason, presence: true
  validates :description, length: { maximum: 1000 }, allow_blank: true
  validates :reportable_id, uniqueness: {
    scope:   %i[reporter_id reportable_type],
    message: :already_reported
  }
  validate :not_reporting_own_content

  # Prohibited items (owner, 2026-10-13): a "prohibited item" report on a
  # listing opens / joins its Flag for the admins; 3 distinct reporters move a
  # live listing to draft (Flag.raise_for_report!). Never fails the report.
  after_create_commit :raise_prohibited_flag, if: :prohibited_item?

  private

  def raise_prohibited_flag
    Flag.raise_for_report!(self)
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { report_id: id })
    nil
  end

  def not_reporting_own_content
    if reportable.is_a?(Listing) && reportable.user_id == reporter_id
      errors.add(:base, "cannot report your own listing")
    end
    if reportable.is_a?(User) && reportable.id == reporter_id
      errors.add(:base, "cannot report yourself")
    end
    if reportable.is_a?(Shop) && reportable.member?(reporter)
      errors.add(:base, "cannot report your own shop")
    end
  end
end
