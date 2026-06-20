class UserWarningSerializer < ApplicationSerializer
  fields :id, :category, :reason, :created_at, :expires_at, :acknowledged_at
  field(:active) { |w| w.active? }
end
