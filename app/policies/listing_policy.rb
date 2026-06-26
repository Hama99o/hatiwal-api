class ListingPolicy < ApplicationPolicy
  def index?    = true
  def show?     = true
  def similar?  = true
  def sold_by?  = true  # public read — any viewer (including guests) may see a seller's sold items
  def viewed?   = true  # authenticated read — any user may list their own view history
  def create?   = true
  def save?     = true

  def update?    = owner?
  def destroy?   = owner?
  def publish?   = owner? && record.draft?
  def unpublish? = owner? && record.active?
  def reserve?   = owner? && record.active?
  def activate?  = owner? && record.reserved?
  def renew?     = owner? && record.active?
  # Sellable from active or reserved; sold is terminal (never from draft/sold).
  def sold?      = owner? && (record.active? || record.reserved?)

  def analytics? = owner?

  def start_conversation?
    record.active?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.nil?

      scope.excluding_blocked_pairs(user)
    end
  end

  private

  def owner? = record.user_id == user.id
end
