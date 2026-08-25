class BackfillConfirmedAtForExistingUsers < ActiveRecord::Migration[8.1]
  # Devise's :confirmable is being switched on for User. The columns it needs
  # (confirmation_token / confirmed_at / confirmation_sent_at) have existed since
  # devise_token_auth installed them, but every row has confirmed_at NULL —
  # because nothing has ever sent a confirmation.
  #
  # Every one of those accounts is a REAL user of a shipped app. Enabling
  # :confirmable without this backfill makes all of them retroactively
  # unconfirmed, and the moment anything is gated on confirmation they are locked
  # out of an app they were using yesterday. So: everyone who exists before the
  # feature exists counts as confirmed. Only accounts created from now on have
  # something to prove.
  #
  # Deliberately NOT reversible-by-guessing: rolling back cannot know which rows
  # it set, and blanking confirmed_at for everybody would be far worse than
  # leaving it populated. Down is a no-op on purpose.
  def up
    # created_at, not Time.current, so the stamp stays honest about the account's
    # own age rather than recording the date of this deploy.
    execute <<~SQL.squish
      UPDATE users
      SET confirmed_at = created_at
      WHERE confirmed_at IS NULL
    SQL
  end

  def down
    # No-op: see above.
  end
end
