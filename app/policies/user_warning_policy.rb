class UserWarningPolicy < ApplicationPolicy
  # A signed-in user may list and acknowledge their OWN warnings. Warnings are
  # only ever issued by admins (outside this API), so there is no create here.
  def index?
    user.present?
  end

  def mark_seen?
    user.present?
  end
end
