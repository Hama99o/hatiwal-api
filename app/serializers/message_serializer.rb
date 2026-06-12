class MessageSerializer < ApplicationSerializer
  fields :id, :body, :kind, :read_at, :created_at

  field(:sender) { |m| { id: m.user_id, name: m.user.full_name } }
end
