class TransactionSerializer < ApplicationSerializer
  # `quantity` is how many UNITS this deal covered (1 for a single-item listing,
  # the column default). Without it on the wire the "who bought how many" ledger
  # docs/SPIKE_LISTING_QUANTITY.md §0b describes cannot be rendered at all — the
  # column exists, the sale records it, and no client could read it.
  #
  # `final_price` is PER UNIT on a multi-unit sale, not the deal total: the
  # seller enters it in a field whose placeholder is the listing's own per-unit
  # price and whose caption says "the price for one item". A client showing a
  # total must multiply.
  fields :id, :status, :final_price, :currency, :quantity, :completed_at, :created_at

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

    { id: l.id, title: l.title, thumbnail_url: l.thumbnail_url, price: l.price, currency: l.currency, status: l.status,
      multi_unit: l.multi_unit?, available_units: l.available_units }
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
