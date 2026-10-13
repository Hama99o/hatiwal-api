class ReportPolicy < ApplicationPolicy
  def index?  = true
  # The Support account is staff, not a member: there is nothing to moderate.
  # A draft is nobody's to see but its seller's, so it is not reportable either:
  # the report list echoes the listing's title (IDOR sweep 2026-10-13).
  def create? = !support_account? && !draft_listing?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(reporter: user)
  end

  private

  def support_account? = record.reportable.is_a?(User) && record.reportable.support_account?
  def draft_listing? = record.reportable.is_a?(Listing) && record.reportable.draft?
end
