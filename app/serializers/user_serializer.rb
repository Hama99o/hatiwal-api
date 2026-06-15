class UserSerializer < ApplicationSerializer
  # Only :id is in the base — all other fields are scoped to their view
  # to prevent PII (email, phone, location) leaking into the :public view.
  fields :id

  # :public — trust-dossier shown to any authenticated user looking at a seller.
  # Must NOT include email, phone, exact coordinates, or any other PII.
  view :public do
    fields :bio, :province, :verified
    field(:firstname) { |u| u.firstname }
    field(:lastname) { |u| u.lastname }
    field(:full_name) { |u| u.full_name }
    field(:listings_count) { |u| u.listings.active.not_expired.count }
    field(:sold_count) { |u| u.listings.sold.count }
    field(:member_since) { |u| u.created_at.strftime("%B %Y") }
    field(:avatar_url) { |u| u.avatar.attached? ? u.avatar.url : nil }
    # Whether the current viewer has blocked this user. Keeps the block/unblock
    # toggle in sync on first open without a separate API call. Defaults to false
    # when no viewer context is available (e.g. unauthenticated — should not
    # happen in practice since the endpoint requires auth).
    field(:blocked) { |u, opts| opts[:current_user]&.blocked?(u) || false }

    # Response rate trust signal — nil when threshold (5 conversations) not met.
    field(:response_rate_percent) { |u| u.response_rate_percent }
    field(:response_time_label) { |u| u.response_time_label&.to_s }
  end

  # :me — full private profile for the authenticated user viewing their own data.
  # Includes PII (email, phone, coordinates) since the owner is entitled to see it.
  view :me do
    fields :email, :firstname, :lastname, :city,
           :phone, :bio, :province, :latitude, :longitude,
           :status, :preferred_language, :seller_mode, :preferred_theme, :verified,
           :created_at
    field(:full_name) { |u| u.full_name }
    field(:avatar_url) { |u| u.avatar.attached? ? u.avatar.url : nil }
    # Dashboard stats for the user's own profile.
    field(:items_active_count) { |u| u.listings.active.count }
    field(:items_sold_count) { |u| u.listings.sold.count }
    # No money total: listings span currencies (AFN/USD/EUR) with no FX rate, so
    # summing them would be meaningless. We surface counts only.
    field(:saved_items_count) { |u| u.saved_listings.count }
    field(:unread_message_count) do |u|
      conversation_ids = Conversation.for_user(u.id).select(:id)
      Message.where(conversation_id: conversation_ids, read_at: nil).where.not(user_id: u.id).count
    end
  end

  view :minimal do
    fields :firstname, :lastname
    field(:full_name) { |u| u.full_name }
  end
end
