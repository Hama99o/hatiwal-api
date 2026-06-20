class ConversationSerializer < ApplicationSerializer
  fields :id, :status, :last_message_at, :created_at

  view :list do
    field(:listing) do |c|
      { id: c.listing_id, title: c.listing.title, thumbnail_url: c.listing.thumbnail_url, status: c.listing.status }
    end
    field(:other_participant) do |c, opts|
      current_user = opts[:current_user]
      other = current_user ? c.other_participant(current_user) : c.buyer
      { id: other.id, name: other.full_name, city: other.city, verified: other.verified, avatar_url: other.avatar.attached? ? other.avatar.url : nil }
    end
    field(:last_message_body) { |c| c.last_message&.body }
    field(:last_message_kind) { |c| c.last_message&.kind }
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
    field(:listing) do |c|
      { id: c.listing_id, title: c.listing.title, price: c.listing.price, currency: c.listing.currency,
        thumbnail_url: c.listing.thumbnail_url, status: c.listing.status, location: c.listing.location }
    end
    field(:buyer)  { |c| b = c.buyer;  { id: c.buyer_id,  name: b.full_name,  city: b.city,  avatar_url: b.avatar.attached? ? b.avatar.url : nil } }
    field(:seller) { |c| s = c.seller; { id: c.seller_id, name: s.full_name, city: s.city, avatar_url: s.avatar.attached? ? s.avatar.url : nil } }
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
