class Api::V1::Users::WarningsController < Api::V1::BaseController
  # The signed-in user's own moderation warnings, so the app can show a
  # "X of N warnings" banner and the reasons. Warnings are issued by admins only.
  def index
    authorize UserWarning
    warnings = current_user.warnings.recent
    render_ok({
      warnings: UserWarningSerializer.render_as_hash(warnings),
      meta: {
        active_count: current_user.active_warnings_count,
        threshold: User::WARNING_BLOCK_THRESHOLD
      }
    })
  end

  # Mark the user's active warnings as seen (dismisses the "new warning" banner).
  def mark_seen
    authorize UserWarning, :mark_seen?
    current_user.active_warnings.where(acknowledged_at: nil).update_all(acknowledged_at: Time.current)
    render_ok({ acknowledged: true })
  end
end
