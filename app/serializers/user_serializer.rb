class UserSerializer < ApplicationSerializer
  fields :id, :email, :firstname, :lastname, :city, :preferred_language, :created_at

  view :public do
    fields :bio, :province, :verified
    field(:full_name) { |u| u.full_name }
    field(:listings_count) { |u| u.listings.active.count }
    field(:sold_count) { |u| u.listings.sold.count }
    field(:member_since) { |u| u.created_at.strftime("%B %Y") }
    field(:avatar_url) { |u| u.avatar.attached? ? u.avatar.url : nil }
  end

  view :me do
    fields :phone, :bio, :province, :latitude, :longitude, :status, :preferred_language, :seller_mode, :preferred_theme, :verified
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
