# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 1): a listing now runs
# 90 days instead of 30. Listings already live get the same 90 days, counted
# from when they went LIVE (`published_at`; `created_at` for a row that predates
# that column) — a draft that sat for a month before publishing gets its full 90.
#
# Only ever EXTENDS: `GREATEST` keeps a later expiry a seller already has (a
# listing renewed last week keeps its renewal). Running it twice changes nothing.
# A live listing created more than 90 days ago stays expired; it is in the
# seller's Expired tab with Relaunch, not deleted. Drafts, sold listings and
# listings with no expiry (NULL = never expires) are left alone.
class ExtendLiveListingsToNinetyDays < ActiveRecord::Migration[8.1]
  ACTIVE = 1
  RESERVED = 2

  def up
    execute <<~SQL.squish
      UPDATE listings
         SET expires_at = GREATEST(expires_at, COALESCE(published_at, created_at) + INTERVAL '90 days')
       WHERE status IN (#{ACTIVE}, #{RESERVED})
         AND expires_at IS NOT NULL
         AND expires_at < COALESCE(published_at, created_at) + INTERVAL '90 days'
    SQL
  end

  def down
    # Irreversible on purpose: shortening a seller's run would hide live listings.
  end
end
