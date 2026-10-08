# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 5):
# "Duplicate" makes a new DRAFT from a listing — its text, price, category,
# place AND PHOTOS — in the place the seller picks: the same one, Me, or another
# shop they are on. The clients then open the draft in the edit form.
#
# Where it may go (the same rules as Listings::MoveService, minus "same place",
# which is the usual choice here):
#   - a shop: the caller is on its team and it is open;
#   - out of the listing's shop (to Me or another shop): its poster while still
#     a member, or the shop's owner or a manager — staff don't copy the shop's
#     goods into their own listings or a second shop (review 2026-10-08).
#
# The photos are COPIED, not shared: each gets a new blob uploaded from the
# original's file. Re-attaching the same blob would tie the two listings
# together — deleting one (has_many_attached purges its blobs) would take the
# other's photos with it.
class Listings::DuplicateService
  Error = Listings::MoveService::Error

  # What a duplicate carries over. Status, expiry, counters, holds, sales and
  # chats belong to the original.
  COPIED = %i[title description price currency condition category_id location address
              latitude longitude negotiable quantity].freeze

  def initialize(listing:, actor:, shop_id:)
    @listing = listing
    @actor   = actor
    @shop_id = shop_id.presence&.to_i
  end

  def call
    # A deleted listing, or one the admin took down, is not copied back into
    # the market (edge-case pass 2026-10-08: a take-down came straight back as
    # a draft, then a live listing, with its text and photos). A sold one is
    # fine: "sell another like this".
    raise Error.new("a removed listing cannot be duplicated", code: :duplicate_removed) if @listing.removed?

    target = target_shop
    copy = Listing.new(@listing.slice(*COPIED).merge(user: @actor, shop: target, status: :draft))

    ActiveRecord::Base.transaction do
      copy.save!
      copy_photos_to(copy)
    end
    copy
  end

  private

  def target_shop
    shop = nil
    if @shop_id
      shop = Shop.find_by(id: @shop_id)
      raise Error.new("you are not on that shop's team", code: :move_not_member, status: :forbidden) unless shop&.member?(@actor)
      raise Error.new("that shop is not open", code: :shop_unavailable) unless shop.active?
    end
    # A copy inside the same shop is any member's; a copy that LEAVES the shop
    # (to Me or to another shop) follows the move rule (Listing#may_leave_shop_by?,
    # review 2026-10-08: staff copied the goods into a second shop).
    return shop if shop&.id == @listing.shop_id || @listing.may_leave_shop_by?(@actor)

    raise Error.new("only its poster or the shop's owner or a manager can copy it out of the shop",
                    code: :duplicate_forbidden, status: :forbidden)
  end

  # In the original's order. `create_and_upload!` uploads while the original's
  # file is open, then the new blob is attached to the copy.
  #
  # A photo whose FILE is gone (a blob row left without its file in storage)
  # is skipped and logged: the other photos and the draft still come through.
  # It used to raise ActiveStorage::FileNotFoundError and fail the whole
  # duplicate (owner bug, 2026-10-08, dev DB).
  def copy_photos_to(copy)
    @listing.images.each do |image|
      blob = image.blob
      blob.open do |file|
        new_blob = ActiveStorage::Blob.create_and_upload!(
          io: file, filename: blob.filename.to_s, content_type: blob.content_type, metadata: blob.metadata.slice("width", "height")
        )
        copy.images.attach(new_blob)
      end
    rescue ActiveStorage::FileNotFoundError
      Rails.logger.warn("[Listings::DuplicateService] listing #{@listing.id}: photo blob #{blob.id} has no file, not copied")
    end
  end
end
