# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md §1.3): WHEN a followed
# search may push. A match never pushes by itself; it is counted, and one
# SavedSearchAlertJob per search runs at the first allowed moment:
#
#   - at most one push per search per WINDOW (matches in between are batched);
#   - never in the user's quiet hours (22:00–07:00 on their own clock);
#   - at most DAILY_CAP alert pushes per user per local day.
#
# The chip badge (SavedSearch#new_matches_count) stays the source of truth:
# these rules only ever delay or merge pushes, they never hide a match.
module SavedSearchAlerts
  WINDOW = 6.hours
  DAILY_CAP = 3
  QUIET_FROM = 22 # local hour the quiet starts
  QUIET_UNTIL = 7 # local hour it ends

  class << self
    # Make sure an alert job is scheduled for this search at the earliest moment
    # the rules allow. One job per search: an earlier slot replaces a later one.
    def schedule(search, at: earliest_send_at(search))
      return if search.alert_scheduled_at && search.alert_scheduled_at <= at

      search.update_columns(alert_scheduled_at: at)
      SavedSearchAlertJob.set(wait_until: at).perform_later(search.id)
    end

    # The first moment the per-search window and the quiet hours allow.
    def earliest_send_at(search, now: Time.current)
      at = [ now, search.last_alerted_at && (search.last_alerted_at + WINDOW) ].compact.max
      quiet_end_after(at, search.user.time_zone)
    end

    def quiet?(time, zone)
      hour = time.in_time_zone(zone).hour
      hour >= QUIET_FROM || hour < QUIET_UNTIL
    end

    # `time` itself when it is not quiet, else the next QUIET_UNTIL o'clock local.
    def quiet_end_after(time, zone)
      return time unless quiet?(time, zone)

      local = time.in_time_zone(zone)
      morning = local.change(hour: QUIET_UNTIL)
      morning += 1.day if local.hour >= QUIET_FROM
      morning
    end

    # The user's alert pushes so far on their local day.
    def pushes_today(user, now: Time.current)
      user.alert_pushes_on == now.in_time_zone(user.time_zone).to_date ? user.alert_pushes_count : 0
    end

    def next_morning(user, now: Time.current)
      now.in_time_zone(user.time_zone).tomorrow.change(hour: QUIET_UNTIL)
    end

    # A count as the user reads digits: ۰–۹ in Pashto, Dari and Urdu.
    def local_number(number, locale)
      text = number.to_s
      %i[ps fa ur].include?(locale.to_sym) ? text.tr("0123456789", "۰۱۲۳۴۵۶۷۸۹") : text
    end

    # One log line per decision, ids and numbers only (tuning after release).
    def log(event, search, **numbers)
      line = "saved_search_alert event=#{event} saved_search_id=#{search.id} user_id=#{search.user_id}"
      numbers.each { |key, value| line += " #{key}=#{value}" }
      Rails.logger.info(line)
    end
  end
end
