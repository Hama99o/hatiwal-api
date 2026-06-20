# Daily sweep that lifts auto-suspensions once a user's warnings have decayed
# below the block threshold. Manual suspensions/bans (auto_blocked = false) are
# never touched here — only an admin can undo those.
class ReinstateDecayedUsersJob < ApplicationJob
  queue_as :default

  def perform
    User.where(status: :suspended, auto_blocked: true).find_each(&:reinstate_if_decayed!)
  end
end
