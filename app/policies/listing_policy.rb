class ListingPolicy < ApplicationPolicy
  def index?  = true
  def show?   = true
  def create? = true
  def save?   = true

  def update?    = owner?
  def destroy?   = owner?
  def publish?   = owner? && record.draft?
  def unpublish? = owner? && record.active?
  def reserve?   = owner? && record.active?
  def activate?  = owner? && record.reserved?
  # Sellable from active or reserved; sold is terminal (never from draft/sold).
  def sold?      = owner? && (record.active? || record.reserved?)

  def start_conversation?
    record.active? && !owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end

  private

  def owner? = record.user_id == user.id
end
