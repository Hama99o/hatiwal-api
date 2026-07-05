class TransactionSerializer < ApplicationSerializer
  fields :id, :status, :final_price, :currency, :completed_at, :created_at

  # "buyer" | "seller" | nil (nil when no viewer context, e.g. the reserve/sold
  # lifecycle response where the caller is always the seller by definition).
  field(:role) do |t, opts|
    current_user = opts[:current_user]
    next nil unless current_user

    current_user.id == t.buyer_id ? "buyer" : "seller"
  end

  field(:listing) do |t|
    l = t.listing
    next nil if l.nil?

    { id: l.id, title: l.title, thumbnail_url: l.thumbnail_url, price: l.price, currency: l.currency, status: l.status }
  end

  field(:buyer) do |t|
    b = t.buyer
    { id: b.id, name: b.full_name, avatar_url: b.avatar.attached? ? b.avatar.url : nil }
  end

  field(:seller) do |t|
    s = t.seller
    { id: s.id, name: s.full_name, avatar_url: s.avatar.attached? ? s.avatar.url : nil }
  end
end
