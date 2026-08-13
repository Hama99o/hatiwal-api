class ConversationSerializer < ApplicationSerializer
  fields :id, :status, :last_message_at, :created_at

  # Shared by both views (TASK-R517) — tells the client which side of this
  # thread the requesting user is on so the inbox can render a Buying/Selling
  # hint. `nil` when there is no current_user (e.g. a serializer unit test
  # that doesn't pass one).
  def self.viewer_role_for(conversation, opts)
    current_user = opts[:current_user]
    return nil unless current_user

    conversation.buyer_id == current_user.id ? "buyer" : "seller"
  end

  view :list do
    field(:viewer_role) { |c, opts| viewer_role_for(c, opts) }
    field(:listing_deleted) { |c| c.listing_deleted? }
    field(:listing) do |c|
      next nil if c.listing_deleted?
      # TASK-J471: price/currency so the inbox row's PriceTag has something to
      # render — plain columns on an already-preloaded association (index
      # `.includes(listing: ...)`), so this adds no N+1.
      { id: c.listing_id, title: c.listing.title, thumbnail_url: c.listing.thumbnail_url, status: c.listing.status,
        price: c.listing.price, currency: c.listing.currency }
    end
    field(:other_participant) do |c, opts|
      current_user = opts[:current_user]
      other = current_user ? c.other_participant(current_user) : c.buyer
      { id: other.id, name: other.full_name, city: other.city, verified: other.verified, avatar_url: other.avatar.attached? ? other.avatar.url : nil }
    end
    # TASK-M913: a retracted last message must not leak its content into the
    # inbox preview — suppress body, keep kind/deleted flag so the client can
    # render its own localized "Message deleted" preview text.
    field(:last_message_body) { |c| lm = c.last_message; lm && !lm.deleted? ? lm.body : nil }
    field(:last_message_kind) { |c| c.last_message&.kind }
    field(:last_message_deleted) { |c| c.last_message&.deleted? || false }
    field(:unread_count) do |c, opts|
      current_user = opts[:current_user]
      next 0 unless current_user

      # Use the precomputed hash when the controller passes it (avoids one
      # COUNT query per row on the index).  Fall back to the model method for
      # callers that don't provide it (e.g. serializer unit tests).
      if opts[:unread_counts]
        opts[:unread_counts].fetch(c.id, 0)
      else
        c.unread_count_for(current_user)
      end
    end
    field(:blocked_with_participant) do |c, opts|
      current_user = opts[:current_user]
      next false unless current_user

      other = c.other_participant(current_user)
      # On the list the controller preloads the viewer's block id-sets so this
      # resolves in memory (no per-row block-existence queries). Fall back to a
      # direct query when the sets aren't provided (single-record callers).
      if opts[:blocked_ids]
        opts[:blocked_ids].include?(other.id) || opts[:blocker_ids].include?(other.id)
      else
        current_user.blocked?(other) || other.blocked?(current_user)
      end
    end
  end

  view :detailed do
    field(:viewer_role) { |c, opts| viewer_role_for(c, opts) }
    field(:listing_deleted) { |c| c.listing_deleted? }
    field(:listing) do |c, opts|
      next nil if c.listing_deleted?
      # TASK-K729: category is included so the mobile thread's reserved/sold
      # recovery notice can offer a "Browse similar in {category}" CTA
      # (pre-filters Browse by category_id) instead of leaving a dead end.
      # Reuses CategorySerializer (the same shape ListingSerializer's three
      # views render) instead of a 4th hand-rolled inline hash.
      current_user = opts[:current_user]
      txn = c.listing.current_sale
      viewer_is_sale_buyer = txn.present? && current_user.present? && txn.buyer_id == current_user.id
      { id: c.listing_id, title: c.listing.title, price: c.listing.price, currency: c.listing.currency,
        thumbnail_url: c.listing.thumbnail_url, status: c.listing.status, location: c.listing.location,
        negotiable: c.listing.negotiable,
        category: CategorySerializer.render_as_hash(c.listing.category),
        # TASK-K729 (review fix, HIGH): boolean-only — true exactly when the
        # viewer IS the buyer the seller committed to for the CURRENT
        # reservation/sale (Listing#current_sale). Lets the mobile thread
        # show "Reserved for you" / "You bought this item" to the buyer who
        # actually won the deal, instead of the generic recovery copy which
        # is FALSE and actively harmful when shown to that same buyer. Never
        # leaks WHO the buyer is when it's someone else — that identity stays
        # owner-scoped in ListingSerializer's `sale` field, never here.
        viewer_is_sale_buyer: viewer_is_sale_buyer,
        # TASK-K729 (review fix, HIGH follow-up): the viewer's OWN transaction
        # id — only ever populated when `viewer_is_sale_buyer` is true, so
        # this never leaks another buyer's transaction id. Lets the mobile
        # "You bought this item" notice open the REV2 ReviewPromptSheet
        # (rate the seller) with a real transactionId instead of the
        # positive close being copy-only with no next step.
        #
        # TASK-K729 (review fix, LOW): additionally gated on `txn.sold?` —
        # `Listing#current_sale` returns the open transaction for `reserved?`
        # too, so without this a still-RESERVED sale (no review to leave yet)
        # would populate this field despite the field's own doc comment
        # promising a reviewable sale. `Review#sale_is_sold` would 422 a
        # premature submit either way, but the field should not over-promise
        # what it actually points at.
        viewer_sale_transaction_id: viewer_is_sale_buyer && txn.sold? ? txn.id : nil,
        # Whether the viewer has already left their review on this sale —
        # lets the client hide the "Rate the seller" CTA once done instead of
        # re-offering a review the server would 422 on as a duplicate.
        viewer_has_reviewed_sale: viewer_is_sale_buyer ? Review.exists?(transaction_id: txn.id, reviewer_id: current_user.id) : nil }
    end
    field(:buyer)  { |c| b = c.buyer;  { id: c.buyer_id,  name: b.full_name,  city: b.city,  verified: b.verified, avatar_url: b.avatar.attached? ? b.avatar.url : nil } }
    field(:seller) { |c| s = c.seller; { id: c.seller_id, name: s.full_name, city: s.city, verified: s.verified, avatar_url: s.avatar.attached? ? s.avatar.url : nil } }
    # The thread screen shows the *other* person (name, avatar, tap-to-profile,
    # block toggle). Mirror the :list view so the detailed payload exposes it too
    # — without this the mobile Conversation screen silently hides those controls.
    field(:other_participant) do |c, opts|
      current_user = opts[:current_user]
      other = current_user ? c.other_participant(current_user) : c.buyer
      { id: other.id, name: other.full_name, city: other.city, verified: other.verified, avatar_url: other.avatar.attached? ? other.avatar.url : nil }
    end
    field(:blocked_with_participant) do |c, opts|
      current_user = opts[:current_user]
      next false unless current_user

      other = c.other_participant(current_user)
      current_user.blocked?(other) || other.blocked?(current_user)
    end
  end
end
