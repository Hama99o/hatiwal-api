class MessageSerializer < ApplicationSerializer
  fields :id, :body, :kind, :read_at, :created_at

  field(:sender) { |m| u = m.user; { id: m.user_id, name: u.full_name, avatar_url: u.avatar.attached? ? u.avatar.url : nil } }
end
