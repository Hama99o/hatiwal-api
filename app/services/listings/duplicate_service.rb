# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 5):
# "Duplicate" makes a new DRAFT from a listing — its text, price, category,
# place AND PHOTOS — in the place the seller picks: the same one, Me, or another
# shop they are on. The clients then open the draft in the edit form.
#
# Where it may go (the same rules as Listings::MoveService, minus "same place",
# which is the usual choice here):
#   - a shop: the caller is on its team and it is open;
#   - Me: a personal listing (its poster), or out of a shop only for the
#     listing's poster or the shop's owner — staff don't copy the shop's goods
#     into their own listings.
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
    if @shop_id
      shop = Shop.find_by(id: @shop_id)
      raise Error.new("you are not on that shop's team", code: :move_not_member, status: :forbidden) unless shop&.member?(@actor)
      raise Error.new("that shop is not open", code: :shop_unavailable) unless shop.active?

      return shop
    end
    return nil if @listing.shop.nil? || @listing.user_id == @actor.id || @listing.shop.owner_id == @actor.id

    raise Error.new("only its poster or the shop's owner can copy it to their own listings",
                    code: :duplicate_forbidden, status: :forbidden)
  end

  # In the original's order. `create_and_upload!` uploads while the original's
  # file is open, then the new blob is attached to the copy.
  def copy_photos_to(copy)
    @listing.images.each do |image|
      blob = image.blob
      blob.open do |file|
        new_blob = ActiveStorage::Blob.create_and_upload!(
          io: file, filename: blob.filename.to_s, content_type: blob.content_type, metadata: blob.metadata.slice("width", "height")
        )
        copy.images.attach(new_blob)
      end
    end
  end
end
