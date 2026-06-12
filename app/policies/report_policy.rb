class ReportPolicy < ApplicationPolicy
  def create? = true

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(reporter: user)
  end
end
