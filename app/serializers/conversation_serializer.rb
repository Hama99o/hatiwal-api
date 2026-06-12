class ConversationSerializer < ApplicationSerializer
  fields :id, :status, :last_message_at, :created_at

  view :list do
    field(:listing) do |c|
      { id: c.listing_id, title: c.listing.title, thumbnail_url: c.listing.thumbnail_url, status: c.listing.status }
    end
    field(:other_participant) do |c, opts|
      current_user = opts[:current_user]
      other = current_user ? c.other_participant(current_user) : c.buyer
      { id: other.id, name: other.full_name, city: other.city }
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
    field(:buyer)  { |c| { id: c.buyer_id,  name: c.buyer.full_name,  city: c.buyer.city } }
    field(:seller) { |c| { id: c.seller_id, name: c.seller.full_name, city: c.seller.city } }
  end
end
