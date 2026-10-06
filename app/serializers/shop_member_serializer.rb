# SHOP-3 — a member of a shop's team, as every member sees the Team list.
# Never an email or a phone: only what a shop chat already shows of a person.
class ShopMemberSerializer < ApplicationSerializer
  field(:user) { |m| u = m.user; { id: u.id, name: u.full_name, avatar_url: u.avatar.attached? ? u.avatar.url : nil } }
  field :role
  field(:joined_at) { |m| m.created_at.iso8601 }
end
