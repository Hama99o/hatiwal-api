class ListingPolicy < ApplicationPolicy
  def index?         = true
  def show?          = true
  def similar?       = true
  def sold_by?       = true  # public read — any viewer (including guests) may see a seller's sold items
  def viewed?        = true  # authenticated read — any user may list their own view history
  def create?        = true
  def save?          = true
  # "Not interested" — any signed-in user may hide/unhide any browsable
  # listing from their own feed; the controller/BaseController already
  # requires authentication, so this simply guards against a nil user.
  def hide?          = user.present?
  def unhide?        = user.present?
  # Authenticated seller action — counts are scoped to current_user.listings
  # in the controller, so any signed-in user is authorised to call this.
  def status_counts? = true

  def update?    = owner?
  def destroy?   = owner?
  def publish?   = owner? && record.draft?
  # SF-B1 — from `live?` (active OR reserved), not `active?`. Reserving no longer
  # takes a listing out of the feed, so "pull it off the market while I finish
  # this deal" has to be a real action a seller can reach from a held listing;
  # otherwise their only route is release-the-hold-then-unpublish, which throws
  # away the record of who it was held for. My::ListingsController#unpublish
  # cancels the open hold as part of the same DB transaction (a draft listing
  # cannot carry a live reservation).
  def unpublish? = owner? && record.live?
  # Deliberately NOT widened: reserving a listing that is already held is
  # release-the-hold-first, not a second hold. (A multi-unit listing keeps
  # status `active` while units are held, so re-reserving a batch to move the
  # hold to another buyer still works — that path never needed `reserved?`.)
  def reserve?   = owner? && record.active?
  # SF-B8 — also allowed on an ACTIVE listing that is holding units for a buyer.
  #
  # A multi-unit listing keeps status `active` while units are held (SF-B2, "a
  # batch does not leave the market because one unit is held"), so `reserved?`
  # alone made a batch's hold IMPOSSIBLE to release: `activate` 403'd, and the
  # only ways out were `unpublish` (takes the whole listing off the market) or
  # re-reserving to a different buyer (moves the hold, never clears it).
  #
  # That is load-bearing for SF-B8, not a tidy-up: its refusal tells the seller to
  # "release the hold first", and the refusal is only ever reachable on a batch —
  # a single-unit hold cannot breach the quantity floor, since `quantity` is
  # already validated greater_than 0. Without this widening the copy would name a
  # way out the seller cannot take.
  #
  # `held_units` (not a fresh query) so this keeps SF-B2's loaded-array guard.
  def activate?  = owner? && (record.reserved? || (record.active? && record.held_units.positive?))
  # SF-B1 — from `live?`. `Listing#expired?` widened to `live?` at the same time,
  # so a reserved listing can now expire and drop out of `browsable`; without
  # this it would expire with no way to renew it.
  def renew?     = owner? && record.live?
  # Sellable while live (active or reserved); sold is terminal (never from
  # draft/sold). Already allowed selling without reserving first.
  def sold?      = owner? && record.live?

  def analytics? = owner?

  # SF-B1 — a reserved listing that the feed now offers MUST be messageable, or
  # the buyer hits a dead end on a listing we just showed them. With no payment
  # holding a deal together, deals fall through constantly; that second
  # interested buyer is the seller's recovery path.
  def start_conversation?
    record.live?
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
