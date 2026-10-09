class UserWarningSerializer < ApplicationSerializer
  fields :id, :category, :created_at, :expires_at, :acknowledged_at
  # In the reader's language when it came from a report (UserWarning#display_reason).
  field(:reason) { |w| w.display_reason }
  field(:active) { |w| w.active? }
end
