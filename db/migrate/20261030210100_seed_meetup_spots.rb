# Data: the draft meetup-spot list (config/meetup_spots.yml) on every database
# that runs migrations, production included — every row switched OFF and marked
# needs_local_check, so nothing shows in the apps until an admin approves it.
# Only adds missing rows, never edits one: safe to run again.
class SeedMeetupSpots < ActiveRecord::Migration[8.1]
  def up
    MeetupSpot.reset_column_information
    say "meetup_spots: #{MeetupSpot.seed_defaults!} added"
  end

  def down
    # The admin may have edited the list since; leave it as it is.
  end
end
