class MessageSerializer < ApplicationSerializer
  fields :id, :kind, :read_at, :created_at, :responds_to_id

  field(:deleted) { |m| m.deleted? }
  field(:deleted_at) { |m| m.deleted_at }

  # Body: suppressed when deleted (tombstone — no content leak)
  field(:body) { |m| m.deleted? ? nil : m.body }

  # Sender is always exposed (tombstones still show who sent — both sides
  # see "Message deleted" but the sender row stays so threading is intact)
  field(:sender) { |m| u = m.user; { id: m.user_id, name: u.full_name, avatar_url: u.avatar.attached? ? u.avatar.url : nil } }

  # Attachment URL: suppressed when deleted
  field(:attachment_url) { |m| m.deleted? ? nil : (m.attachment.attached? ? m.attachment.url : nil) }

  # For offer and offer_counter kinds the body encodes "amount|currency|listedPrice".
  # We expose the parsed fields so the mobile client never has to split the body string.
  # Both are suppressed when deleted.
  field(:offer_amount) do |m|
    next nil if m.deleted?
    next nil unless m.offer? || m.offer_counter?

    parts = m.body.split("|")
    parts[0].to_f
  end

  field(:offer_currency) do |m|
    next nil if m.deleted?
    next nil unless m.offer? || m.offer_counter?

    parts = m.body.split("|")
    parts[1]
  end
end
