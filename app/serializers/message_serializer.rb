class MessageSerializer < ApplicationSerializer
  fields :id, :body, :kind, :read_at, :created_at, :responds_to_id

  field(:sender) { |m| u = m.user; { id: m.user_id, name: u.full_name, avatar_url: u.avatar.attached? ? u.avatar.url : nil } }
  field(:attachment_url) { |m| m.attachment.attached? ? m.attachment.url : nil }

  # For offer and offer_counter kinds the body encodes "amount|currency|listedPrice".
  # We expose the parsed fields so the mobile client never has to split the body string.
  field(:offer_amount) do |m|
    next nil unless m.offer? || m.offer_counter?

    parts = m.body.split("|")
    parts[0].to_f
  end

  field(:offer_currency) do |m|
    next nil unless m.offer? || m.offer_counter?

    parts = m.body.split("|")
    parts[1]
  end
end
