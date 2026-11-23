# A website Flatline watches.
#
# Status rules:
# - "pending" until the first result comes in
# - "up" or "warning" straight from the latest successful result
# - "down" once `failure_threshold` checks in a row have failed; the down
#   period starts at the first of those failures
# - "paused" while the owner has stopped watching it
class Check < ApplicationRecord
  # Fixed for the first version.
  INTERVALS = [ 1, 5, 15, 60 ].freeze
  DEFAULT_INTERVAL = 5
  DEFAULT_FAILURE_THRESHOLD = 2
  TIMEOUT = 30.seconds
  SLOW_RESPONSE = 5.seconds
  CERTIFICATE_WARNING = 14.days
  RECHECK_AFTER = 1.minute
  HISTORY = 6.months
  BAR_DAYS = 90

  # A check is due if it is due within this window, so small delays in the
  # every-minute scheduler don't push it back a whole extra minute.
  SCHEDULE_SLACK = 30.seconds

  # How late a result may arrive and still count the time since the previous
  # one. Longer gaps (Flatline stopped or offline) aren't counted either way.
  GAP_SLACK = 2.minutes

  STATUSES = %w[pending up warning down paused].freeze

  has_many :results, class_name: "CheckResult", dependent: :delete_all
  has_many :down_periods, dependent: :delete_all
  has_many :daily_summaries, dependent: :delete_all

  normalizes :name, :group_name, :required_phrase, with: ->(value) { value.strip.presence }
  normalizes :url, with: ->(value) {
    value = value.strip
    value.match?(%r{\A[a-z][a-z0-9+.-]*://}i) || value.empty? ? value : "https://#{value}"
  }

  validates :name, presence: true, length: { maximum: 100 }
  validates :url, presence: true, length: { maximum: 2000 }
  validate :url_must_be_a_website
  validates :group_name, length: { maximum: 100 }
  validates :required_phrase, length: { maximum: 500 }
  validates :interval_minutes, inclusion: { in: INTERVALS, message: "must be 1, 5, 15 or 60 minutes" }
  validates :failure_threshold, numericality: { only_integer: true, in: 1..10 }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(paused_at: nil) }
  scope :due, ->(now = Time.current) {
    active.where(next_check_at: nil).or(active.where(next_check_at: ..(now + SCHEDULE_SLACK)))
  }

  before_create { self.status_changed_at ||= Time.current }
  after_create_commit :check_now

  def self.group_names
    where.not(group_name: nil).distinct.order(:group_name).pluck(:group_name)
  end

  # Down first, then by group (websites without one last) and name.
  def self.in_overview_order(checks)
    checks.sort_by do |check|
      [ check.down? ? 0 : 1, check.group_name ? 0 : 1, check.group_name.to_s.downcase, check.name.downcase ]
    end
  end

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  def interval
    interval_minutes.minutes
  end

  def host_and_path
    uri = URI(url)
    path = uri.path == "/" ? "" : uri.path
    "#{uri.host}#{path}"
  rescue URI::Error
    url
  end

  # Checks it straight away, then on its interval.
  def check_now
    update_column(:next_check_at, Time.current + interval) unless paused?
    RunCheckJob.perform_later(self) unless paused?
  end

  # After settings are saved: check straight away if what's being checked
  # changed, or bring the next check forward when the interval got shorter.
  def reschedule_after_edit
    return if paused?

    if saved_change_to_url? || saved_change_to_required_phrase?
      check_now
    elsif saved_change_to_interval_minutes? && next_check_at && next_check_at > Time.current + interval
      update_column(:next_check_at, Time.current + interval)
    end
  end

  def pause!(at = Time.current)
    return if paused?

    transaction do
      close_down_period!(at) if down?
      update!(paused_at: at, status: "paused", status_changed_at: at,
        consecutive_failures: 0, failing_since: nil, accounted_until: nil)
    end
  end

  def resume!(at = Time.current)
    return unless paused?

    update!(paused_at: nil, status: "pending", status_changed_at: at)
    check_now
  end

  # Runs the check and records what it finds. Failures only count when
  # Flatline can reach the internet itself (see Connectivity).
  def run!(at = Time.current)
    result = Probe.new(url:, required_phrase:).call

    if result.down? && !Connectivity.online?
      Setting.mark_offline!(at)
      update_columns(next_check_at: at + RECHECK_AFTER, accounted_until: nil) unless reload.paused?
      return :ignored
    end

    Setting.mark_online!
    record!(result, at)
  end

  def record!(result, at = Time.current)
    transaction do
      reload
      return :ignored if paused?

      span_start = accounted_until if accounted_until && at - accounted_until <= expected_gap
      reset_failure_streak if span_start.nil? && !down?
      was_down = down?

      results.create!(checked_at: at, outcome: result.outcome, message: result.message,
        response_ms: result.response_ms, http_status: result.http_status)

      DailySummary.add_result(self, at, warning: result.warning?)
      DailySummary.add_time(self, span_start, at, :monitored_seconds)
      DailySummary.add_time(self, span_start, at, :down_seconds) if was_down

      if result.down?
        record_failure(result, at, was_down)
      else
        close_down_period!(at) if was_down
        reset_failure_streak
        change_status(result.outcome, at)
      end

      update!(last_checked_at: at, last_message: result.message, last_response_ms: result.response_ms,
        last_http_status: result.http_status, cert_expires_at: result.cert_expires_at, accounted_until: at)
      result.outcome
    end
  end

  def current_down_period
    down_periods.ongoing.order(:started_at).last
  end

  private
    def record_failure(result, at, was_down)
      self.consecutive_failures += 1
      self.failing_since ||= at
      self.next_check_at = at + RECHECK_AFTER

      if !was_down && consecutive_failures >= failure_threshold
        change_status("down", failing_since)
        down_periods.create!(started_at: failing_since, reason: result.message)
        DailySummary.add_time(self, failing_since, at, :down_seconds)
      end
    end

    def close_down_period!(at)
      down_periods.ongoing.update_all(ended_at: at)
    end

    def reset_failure_streak
      self.consecutive_failures = 0
      self.failing_since = nil
    end

    def change_status(new_status, at)
      return if status == new_status

      self.status = new_status
      self.status_changed_at = at
    end

    def expected_gap
      [ interval, RECHECK_AFTER ].max + GAP_SLACK
    end

    def url_must_be_a_website
      uri = URI.parse(url.to_s)
      unless uri.is_a?(URI::HTTP) && (uri.host.to_s.include?(".") || uri.host == "localhost")
        errors.add(:url, "must be a website address, like https://example.com")
      end
    rescue URI::Error
      errors.add(:url, "must be a website address, like https://example.com")
    end
end
