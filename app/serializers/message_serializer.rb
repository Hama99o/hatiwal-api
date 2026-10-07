class MessageSerializer < ApplicationSerializer
  fields :id, :kind, :read_at, :created_at, :responds_to_id

  field(:deleted) { |m| m.deleted? }
  # A server notice ({notice, shop_id, name}), so each viewer reads it in their
  # own language; `body` is the fallback older apps show. Only "listing_moved"
  # (Listings::MoveService) today. Nil on every other message.
  field(:notice) { |m| m.system? && m.context.is_a?(Hash) ? m.context.slice("notice", "shop_id", "name") : nil }
  field(:deleted_at) { |m| m.deleted_at }

  # Body: suppressed when deleted (tombstone — no content leak)
  field(:body) { |m| m.deleted? ? nil : m.body }

  # Sender is always exposed (tombstones still show who sent — both sides
  # see "Message deleted" but the sender row stays so threading is intact)
  # SHOP-1/2: the seller side of a chat with a shop writes AS the shop — its
  # name and logo, never the owner's (ConversationSerializer.person_block).
  field(:sender) do |m|
    u = m.user
    # SHOP-3: any member of the chat's shop writes as the shop, not only the seller.
    shop = m.conversation&.shop_face if m.conversation&.written_as_shop?(m.user_id)
    next { id: m.user_id, name: shop.name, avatar_url: shop.logo_url, as_shop: true } if shop

    { id: m.user_id, name: u.full_name, avatar_url: u.avatar.attached? ? u.avatar.url : nil }
  end

  # SHOP-3 "replied by": WHICH teammate wrote a shop message, for the shop's
  # team only (their own messages included, apps-6a). The key is ABSENT for the
  # buyer and for anyone outside the shop. A viewer qualifies when it is on the
  # chat's seller side (REST: `current_user`), or the payload goes to the
  # members-only live stream (`team: true`, BroadcastMessageJob).
  field(:sent_by, if: ->(_name, m, opts) { sent_by_visible?(m, opts) }) do |m|
    { id: m.user_id, name: m.user.full_name }
  end

  def self.sent_by_visible?(message, opts)
    conversation = message.conversation
    return false unless conversation&.written_as_shop?(message.user_id)

    opts[:team] == true || (opts[:current_user].present? && conversation.seller_side?(opts[:current_user]))
  end

  # Attachment URL: suppressed when deleted
  field(:attachment_url) { |m| m.deleted? ? nil : (m.attachment.attached? ? m.attachment.url : nil) }

  # For offer and offer_counter kinds the body encodes "amount|currency|listedPrice".
  # We expose the parsed fields so the mobile client never has to split the body string.
  # All three are suppressed when deleted.
  #
  # `Message#offer_kind?` replaces the `m.offer? || m.offer_counter?` pair that was
  # written out once per field here — see its note on the model.
  field(:offer_amount) do |m|
    next nil if m.deleted?
    next nil unless m.offer_kind?

    parts = m.body.split("|")
    parts[0].to_f
  end

  field(:offer_currency) do |m|
    next nil if m.deleted?
    next nil unless m.offer_kind?

    parts = m.body.split("|")
    parts[1]
  end

  # SF-B11 — how many units this offer is for, on a MULTI-UNIT listing only.
  #
  # A real column (not parsed out of `body` like the two fields above): the body's
  # pipe encoding is already load-bearing on both clients and in `hatiwal-web`,
  # and appending a 4th segment to it would have changed the meaning of a field
  # every one of them already parses. This is additive instead — a new key that
  # every existing client simply ignores.
  #
  # `nil` is the answer for EVERY message that is not an offer, every offer on a
  # single-item listing, and every offer whose sender did not state a quantity —
  # including all of them sent before this ticket. It means "unspecified", NOT
  # "one": a client shows its agreed-quantity UI only for a real number, and
  # treats the absence as one unit. That is what keeps a single-item listing
  # untouched end to end (`Message#discard_meaningless_offer_quantity` never lets
  # a value reach the column for one).
  #
  # HOW A CLIENT READS THE AGREED QUANTITY: an accept is a separate message
  # (`kind: "offer_accepted"`) whose `responds_to_id` points at the offer it
  # answers, so the agreed terms are read off THAT offer — its `offer_amount`
  # and now its `offer_quantity` — exactly as mobile's `reserveAfterAccept`
  # already reads `message.offerAmount` from the offer bubble it was tapped on.
  # Mark-sold then passes it straight through as `PUT /my/listings/:id/sold`'s
  # existing `quantity` param; no new endpoint and no change to that contract.
  field(:offer_quantity) do |m|
    next nil if m.deleted?
    next nil unless m.offer_kind?

    m.offer_quantity
  end
end
