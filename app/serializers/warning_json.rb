# frozen_string_literal: true

# The latest strike of a user or a shop, as the apps show it (owner, 2026-10-16:
# warnings surfaced in the banners). `nil` when there is none. Shared by the
# user (/me) and the members-only shop view, so both speak the same shape.
module WarningJson
  module_function

  def latest(subject)
    warning = subject.warnings.recent.first
    return nil unless warning

    {
      category: warning.category,
      reason: warning.display_reason,
      created_at: warning.created_at.iso8601,
      listing_title: warning.listing&.title
    }
  end
end
