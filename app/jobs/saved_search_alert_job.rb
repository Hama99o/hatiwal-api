# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md §1.3–1.4): the one place a
# saved-search push is decided and sent. Runs at the moment SavedSearchAlerts
# scheduled; re-checks everything, because time has passed since the match:
#
#   off      the search was unfollowed / the account switch turned off
#   stale    every pending listing is gone (sold, removed, blocked): nothing sent
#   window   pushed less than 6 h ago: rescheduled
#   quiet    22:00–07:00 on the user's clock: rescheduled to 07:00
#   capped   3 alert pushes already today: rescheduled to tomorrow 07:00
#   no_token the user cannot be pushed to (the chip badge still shows it)
#   sent     one push: "New match for «label»" or "N new items for «label»"
#
# Each decision is one log line (SavedSearchAlerts.log), ids and numbers only.
class SavedSearchAlertJob < ApplicationJob
  queue_as :default

  def perform(saved_search_id)
    search = SavedSearch.includes(:user, :category).find_by(id: saved_search_id)
    return unless search

    search.update_columns(alert_scheduled_at: nil)
    user = search.user
    hits = search.alert_hits.unannounced.includes(:listing).order(:id).to_a
    return if hits.empty? && search.pending_alert_count.zero?

    return finish(search, hits, :off) unless search.alert? && user.saved_search_alerts?

    live = hits.select { |hit| hit.listing && search.matches?(hit.listing) }
    return finish(search, hits, :stale) if live.empty?

    now = Time.current
    if search.last_alerted_at && now < search.last_alerted_at + SavedSearchAlerts::WINDOW
      return reschedule(search, :window, search.last_alerted_at + SavedSearchAlerts::WINDOW)
    end
    return reschedule(search, :quiet, SavedSearchAlerts.quiet_end_after(now, user.time_zone)) if SavedSearchAlerts.quiet?(now, user.time_zone)
    if SavedSearchAlerts.pushes_today(user) >= SavedSearchAlerts::DAILY_CAP
      return reschedule(search, :capped, SavedSearchAlerts.next_morning(user))
    end

    token = user.live_push_token
    return finish(search, hits, :no_token) unless token

    push(search, user, token, live)
    finish(search, hits, :sent, count: live.size)
  end

  private

  def reschedule(search, event, at)
    SavedSearchAlerts.log(event, search)
    search.update_columns(alert_scheduled_at: at)
    self.class.set(wait_until: at).perform_later(search.id)
  end

  # The pending matches are dealt with (announced, or not worth announcing).
  def finish(search, hits, event, count: 0)
    SavedSearchAlertHit.where(id: hits.map(&:id)).update_all(alerted_at: Time.current)
    columns = { pending_alert_count: 0 }
    columns[:last_alerted_at] = Time.current if event == :sent
    search.update_columns(columns)
    SavedSearchAlerts.log(event, search, **(event == :sent ? { count: count } : {}))
  end

  def push(search, user, token, live)
    listing = live.last.listing
    title, body = I18n.with_locale(user.push_locale) do
      label = search.query.presence || search.category&.name_for(I18n.locale) || I18n.t("push.saved_search.your_search")
      if live.size == 1
        [ I18n.t("push.saved_search.one_title", label: label), I18n.t("push.saved_search.one_body", title: listing.title) ]
      else
        [ I18n.t("push.saved_search.many_title", count: SavedSearchAlerts.local_number(live.size, I18n.locale), label: label), I18n.t("push.saved_search.many_body") ]
      end
    end

    result = Notifications::ExpoPushService.deliver(
      token: token, title: title, body: body, data: { type: "saved_search", savedSearchId: search.id }
    )
    user.update_columns(push_token: nil, push_token_client: nil) if result.error.to_s == "DeviceNotRegistered"
    count_push(user)
  end

  def count_push(user)
    today = Time.current.in_time_zone(user.time_zone).to_date
    count = user.alert_pushes_on == today ? user.alert_pushes_count + 1 : 1
    user.update_columns(alert_pushes_on: today, alert_pushes_count: count)
  end
end
