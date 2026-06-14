class SavedSearchPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user.present?
  end

  def destroy?
    user.present? && record.user_id == user.id
  end
end
