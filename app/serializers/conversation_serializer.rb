class ConversationSerializer < ApplicationSerializer
  fields :id, :status, :last_message_at, :created_at

  view :list do
    field(:listing) do |c|
      { id: c.listing_id, title: c.listing.title, thumbnail_url: c.listing.thumbnail_url, status: c.listing.status }
    end
    field(:other_participant) do |c, opts|
      current_user = opts[:current_user]
      other = current_user ? c.other_participant(current_user) : c.buyer
      { id: other.id, name: other.full_name, city: other.city, avatar_url: other.avatar.attached? ? other.avatar.url : nil }
    end
    field(:last_message_body) do |c|
      c.messages.ordered.last&.body
    end
    field(:unread_count) do |c, opts|
      current_user = opts[:current_user]
      next 0 unless current_user

      c.messages.where(read_at: nil).where.not(user_id: current_user.id).count
    end
  end

  view :detailed do
    field(:listing) do |c|
      { id: c.listing_id, title: c.listing.title, price: c.listing.price, currency: c.listing.currency,
        thumbnail_url: c.listing.thumbnail_url, status: c.listing.status, location: c.listing.location }
    end
    field(:buyer)  { |c| b = c.buyer;  { id: c.buyer_id,  name: b.full_name,  city: b.city,  avatar_url: b.avatar.attached? ? b.avatar.url : nil } }
    field(:seller) { |c| s = c.seller; { id: c.seller_id, name: s.full_name, city: s.city, avatar_url: s.avatar.attached? ? s.avatar.url : nil } }
  end
end
