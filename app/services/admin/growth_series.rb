# New-records-per-period series for the admin dashboard charts.
#
# Bucketed on KABUL time, not UTC. config.time_zone is unset, so Rails runs in
# UTC, while Kabul is UTC+04:30: a UTC day boundary lands at 04:30 local, so
# everyone who signed up between midnight and 04:30 in Kabul was counted on the
# previous day (and week, and month on the 1st). The zone is passed to
# Groupdate here rather than set globally, because config.time_zone changes
# timestamp behaviour across the whole API.
#
# Weeks start on SATURDAY, the first day of the working week in Afghanistan.
class Admin::GrowthSeries
  TIME_ZONE = "Asia/Kabul".freeze
  WEEK_START = :saturday

  # How far back each view goes.
  PERIODS = {
    "week" => { last: 12, label: "Weekly (last 12 weeks)" },
    "month" => { last: 12, label: "Monthly (last 12 months)" },
    "year" => { last: 5, label: "Yearly (last 5 years)" }
  }.freeze
  DEFAULT_PERIOD = "week".freeze

  def self.normalize(period)
    PERIODS.key?(period.to_s) ? period.to_s : DEFAULT_PERIOD
  end

  # => { Date => count }, every bucket present (zeros included) so the chart
  # shows a quiet week as a dip rather than skipping it.
  def self.for(relation, period, column: :created_at)
    period = normalize(period)
    options = { last: PERIODS[period][:last], time_zone: TIME_ZONE }
    # Groupdate rejects week_start on any period but week.
    options[:week_start] = WEEK_START if period == "week"
    relation.group_by_period(period, column, **options).count
  end
end
