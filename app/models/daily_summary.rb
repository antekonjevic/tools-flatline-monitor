# One row per website per day, kept up to date as results come in, so the
# 90-day bars and uptime percentage load without scanning every result.
class DailySummary < ApplicationRecord
  belongs_to :check

  # The days shown as bars, oldest first, ending today.
  def self.bar_days(today = Time.zone.today)
    (today - (Check::BAR_DAYS - 1))..today
  end

  # { check_id => { day => summary } } for the bar days.
  def self.for_bars(checks)
    where(check_id: checks.map(&:id), day: bar_days)
      .group_by(&:check_id)
      .transform_values { |rows| rows.index_by(&:day) }
  end

  # Adds the time between two moments to a column, split across the days
  # (in the configured time zone) that it covers.
  def self.add_time(check, from, to, column)
    return if from.nil? || to.nil? || to <= from

    cursor = from
    while cursor < to
      day = cursor.in_time_zone.to_date
      segment_end = [ day.next_day.in_time_zone, to ].min
      increment(check, day, column => (segment_end - cursor).round)
      cursor = segment_end
    end
  end

  def self.add_result(check, at, warning:)
    increment(check, at.in_time_zone.to_date, checks_count: 1, warnings_count: warning ? 1 : 0)
  end

  def self.increment(check, day, counts)
    counts = counts.select { |_column, amount| amount.positive? }
    return if counts.empty?

    summary = find_or_create_by!(check_id: check.id, day: day)
    update_counters(summary.id, counts)
  end

  # Share of watched time the website was not down, or nil when it hasn't
  # been watched at all. Paused time is never watched, so it doesn't count.
  def self.uptime(summaries)
    monitored = summaries.sum(&:monitored_seconds)
    return nil if monitored.zero?

    down = [ summaries.sum(&:down_seconds), monitored ].min
    (monitored - down).fdiv(monitored)
  end

  def bar_status
    if down_seconds.positive? then "down"
    elsif warnings_count.positive? then "warning"
    elsif monitored_seconds.positive? || checks_count.positive? then "up"
    else "none"
    end
  end

  def uptime
    self.class.uptime([ self ])
  end
end
