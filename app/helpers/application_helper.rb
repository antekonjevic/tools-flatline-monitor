module ApplicationHelper
  STATUS_LABELS = {
    "pending" => "Pending", "up" => "Up", "warning" => "Warning", "down" => "Down", "paused" => "Paused"
  }.freeze

  def status_label(status)
    STATUS_LABELS.fetch(status, status.to_s.humanize)
  end

  def status_badge(check)
    tag.span(status_label(check.status), class: "badge badge-#{check.status}")
  end

  # "Up for 3 days", "Down for 12 minutes", "Waiting for the first check"
  def status_with_duration(check)
    if check.pending? || check.status_changed_at.nil?
      return check.consecutive_failures.positive? ? "Not confirmed yet" : "Waiting for the first check"
    end

    "#{status_label(check.status)} for #{distance_of_time_in_words(check.status_changed_at, Time.current)}"
  end

  # Compact durations for down periods: "45 s", "12 min", "2 h 14 min", "3 d 4 h".
  def short_duration(seconds)
    seconds = seconds.to_i
    return "#{seconds} s" if seconds < 60

    minutes = seconds / 60
    return "#{minutes} min" if minutes < 60

    hours, minutes = minutes.divmod(60)
    return [ "#{hours} h", (minutes.positive? ? "#{minutes} min" : nil) ].compact.join(" ") if hours < 24

    days, hours = hours.divmod(24)
    [ "#{days} d", (hours.positive? ? "#{hours} h" : nil) ].compact.join(" ")
  end

  # Rounded down, so a little downtime never shows as 100%.
  def uptime_text(uptime)
    return "—" if uptime.nil?
    return "100%" if uptime >= 1

    "#{format("%.2f", (uptime * 10_000).floor / 100.0)}%"
  end

  def uptime_for(check, summaries)
    DailySummary.uptime(summaries.fetch(check.id, {}).values)
  end

  # "38 up · 2 down · 1 paused"
  def totals_line(checks)
    counts = checks.map(&:status).tally
    parts = [ "#{counts.fetch("up", 0)} up" ]
    parts << "#{counts["warning"]} warning" if counts["warning"]
    parts << "#{counts.fetch("down", 0)} down"
    parts << "#{counts["paused"]} paused" if counts["paused"]
    parts << "#{counts["pending"]} pending" if counts["pending"]
    parts.join(" · ")
  end

  def bar_title(day, summary)
    date = l(day, format: :bar)
    return "#{date}: no data" if summary.nil? || summary.bar_status == "none"

    details = []
    details << "down #{short_duration(summary.down_seconds)}" if summary.down_seconds.positive?
    details << "#{summary.warnings_count} #{"warning".pluralize(summary.warnings_count)}" if summary.warnings_count.positive?
    details << "#{uptime_text(summary.uptime)} uptime" if summary.uptime
    "#{date}: #{details.join(", ")}"
  end

  # A <time> element that reads "3 minutes ago" and shows the exact time on hover.
  def time_ago_tag(time)
    return "never" if time.nil?

    tag.time("#{time_ago_in_words(time)} ago", datetime: time.iso8601, title: l(time, format: :full))
  end

  def format_time(time, format = :history)
    time && l(time.in_time_zone, format:)
  end

  # The second line under a website's status: why it's down or has a
  # warning, or that a failure is being rechecked.
  def status_reason(check)
    if check.down?
      check.current_down_period&.reason || check.last_message
    elsif check.consecutive_failures.positive?
      "#{check.last_message.presence || "Last check failed"}, checking again"
    elsif check.warning?
      check.last_message
    end
  end

  def last_check_at
    Check.maximum(:last_checked_at)
  end

  # Links to a watched website. Addresses are validated as http(s) on save;
  # this guards the href again. No referrer, so the board's secret link
  # never reaches the website.
  def website_link(check, text = check.url, **options)
    return text unless check.url.to_s.match?(%r{\Ahttps?://}i)

    tag.a(text, href: check.url, rel: "noopener noreferrer", target: "_blank", **options)
  end

  THEMES = %w[light dark].freeze

  # The owner's light/dark choice, kept in a cookie by the theme switch so
  # the page is rendered in the right colors from the first paint. "system"
  # follows the device.
  def theme_preference
    cookies[:theme].presence_in(THEMES) || "system"
  end

  def forced_theme
    theme_preference.presence_in(THEMES)
  end

  def nav_link(name, path)
    link_to name, path, aria: { current: ("page" if current_page?(path)) }
  end

  def interval_options
    labels = { 1 => "Every minute", 60 => "Every hour" }
    Check::INTERVALS.map { |minutes| [ labels.fetch(minutes, "Every #{minutes} minutes"), minutes ] }
  end
end
