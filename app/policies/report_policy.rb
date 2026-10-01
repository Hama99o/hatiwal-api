class ReportPolicy < ApplicationPolicy
  def index?  = true
  # The Support account is staff, not a member: there is nothing to moderate.
  def create? = !(record.reportable.is_a?(User) && record.reportable.support_account?)

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(reporter: user)
  end
end
