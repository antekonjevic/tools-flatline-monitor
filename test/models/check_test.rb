require "test_helper"

class CheckTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.local(2026, 11, 20, 12, 0, 0) }

  test "adds https:// to a bare address" do
    assert_equal "https://example.com", Check.new(url: " example.com ").url
  end

  test "rejects addresses that aren't websites" do
    %w[ftp://example.com javascript:alert(1) https://nodot].each do |url|
      check = Check.new(name: "x", url: url)
      assert_not check.valid?, "#{url} should be invalid"
      assert check.errors.of_kind?(:url, :invalid) || check.errors[:url].any?
    end
  end

  test "only allows the fixed intervals" do
    assert_not Check.new(name: "x", url: "https://example.com", interval_minutes: 7).valid?
    assert Check.new(name: "x", url: "https://example.com", interval_minutes: 15).valid?
  end

  test "is checked straight away when added" do
    assert_enqueued_with(job: RunCheckJob) { Check.create!(name: "x", url: "https://example.com") }
    assert_equal Time.current + 5.minutes, Check.last.next_check_at
  end

  test "first result sets the status" do
    check = create_check

    check.record!(probe_result("up"))

    assert check.up?
    assert_equal Time.current, check.status_changed_at
    assert_equal 1, check.results.count
  end

  test "one failure doesn't count as down, but rechecks in a minute" do
    check = create_check
    check.record!(probe_result("up"))

    travel 5.minutes
    check.record!(probe_result("down", message: "HTTP 500"))

    assert check.up?
    assert_equal 1, check.consecutive_failures
    assert_equal Time.current + 1.minute, check.next_check_at
    assert_empty check.down_periods
  end

  test "goes down after enough failures in a row, from the first failure" do
    check = create_check
    check.record!(probe_result("up"))
    travel 5.minutes
    first_failure_at = Time.current
    check.record!(probe_result("down", message: "Connection refused"))
    travel 1.minute
    check.record!(probe_result("down", message: "Connection refused"))

    assert check.down?
    assert_equal first_failure_at, check.status_changed_at
    period = check.down_periods.sole
    assert_equal first_failure_at, period.started_at
    assert_nil period.ended_at
    assert_equal "Connection refused", period.reason
  end

  test "a success in between resets the failure count" do
    check = create_check
    check.record!(probe_result("down"))
    travel 1.minute
    check.record!(probe_result("up"))
    travel 5.minutes
    check.record!(probe_result("down"))

    assert check.up?
    assert_equal 1, check.consecutive_failures
  end

  test "coming back up closes the down period" do
    check = create_check(failure_threshold: 1)
    check.record!(probe_result("up"))
    travel 5.minutes
    check.record!(probe_result("down"))
    travel 1.minute
    check.record!(probe_result("down"))
    travel 1.minute
    check.record!(probe_result("up"))

    assert check.up?
    period = check.down_periods.sole
    assert_equal 2.minutes, period.duration
    assert_equal 0, check.consecutive_failures
  end

  test "a warning is not down" do
    check = create_check
    check.record!(probe_result("warning", message: "Slow response (6.1 s)"))

    assert check.warning?
    assert_equal "Slow response (6.1 s)", check.last_message
  end

  test "daily summary counts watched time and downtime" do
    check = create_check(failure_threshold: 2)
    check.record!(probe_result("up"))            # 12:00
    travel 5.minutes
    check.record!(probe_result("up"))            # 12:05, 5 min up
    travel 5.minutes
    check.record!(probe_result("down"))          # 12:10, first failure
    travel 1.minute
    check.record!(probe_result("down"))          # 12:11, confirmed down from 12:10
    travel 1.minute
    check.record!(probe_result("up"))            # 12:12, back up

    summary = check.daily_summaries.sole
    assert_equal 12.minutes.to_i, summary.monitored_seconds
    assert_equal 2.minutes.to_i, summary.down_seconds
    assert_equal 5, summary.checks_count
    assert_equal "down", summary.bar_status
    assert_in_delta 10.0 / 12, summary.uptime, 0.0001
  end

  test "time is split across midnight" do
    travel_to Time.zone.local(2026, 11, 20, 23, 58, 0)
    check = create_check
    check.record!(probe_result("up"))
    travel 5.minutes
    check.record!(probe_result("up"))

    seconds = check.daily_summaries.order(:day).pluck(:day, :monitored_seconds)
    assert_equal [ [ Date.new(2026, 11, 20), 120 ], [ Date.new(2026, 11, 21), 180 ] ], seconds
  end

  test "a long gap isn't counted either way" do
    check = create_check
    check.record!(probe_result("up"))
    travel 3.hours
    check.record!(probe_result("up"))

    assert_equal 0, check.daily_summaries.sole.monitored_seconds
  end

  test "a stale failure streak is forgotten after a gap" do
    check = create_check
    check.record!(probe_result("down"))
    travel 3.hours
    check.record!(probe_result("down"))

    assert_not check.down?
    assert_equal 1, check.consecutive_failures
  end

  test "pausing ends downtime and stops the clock" do
    check = create_check(failure_threshold: 1)
    check.record!(probe_result("down"))
    travel 10.minutes

    check.pause!

    assert check.paused?
    assert_equal 10.minutes, check.down_periods.sole.duration
    assert_nil check.accounted_until
  end

  test "results that arrive after pausing are thrown away" do
    check = create_check
    check.pause!

    assert_equal :ignored, check.record!(probe_result("down"))
    assert_empty check.results
  end

  test "resuming checks straight away" do
    check = create_check
    check.pause!

    assert_enqueued_with(job: RunCheckJob) { check.resume! }
    assert check.pending?
  end

  test "a failure while Flatline is offline is ignored" do
    check = create_check
    stub_request(:get, "https://example.com/").to_raise(SocketError)
    stub_connectivity(online: false)

    assert_equal :ignored, check.run!

    assert_empty check.reload.results
    assert_equal 0, check.consecutive_failures
    assert Setting.instance.offline?
    assert_equal Time.current + 1.minute, check.next_check_at
  end

  test "a failure while Flatline is online is recorded" do
    check = create_check
    stub_request(:get, "https://example.com/").to_raise(Errno::ECONNREFUSED)
    stub_connectivity(online: true)
    Setting.mark_offline!

    check.run!

    assert_equal "Connection refused", check.reload.results.sole.message
    assert_not Setting.instance.offline?
  end

  test "a success proves Flatline is online" do
    check = create_check
    stub_request(:get, "https://example.com/").to_return(status: 200)
    Setting.mark_offline!

    check.run!

    assert_not Setting.instance.offline?
    assert_not_requested :head, Connectivity::TARGETS.first
  end

  test "overview order puts down first, then group and name, ungrouped last" do
    a = create_check(name: "b", group_name: "Zeta")
    b = create_check(name: "a", group_name: "Alpha")
    c = create_check(name: "c", group_name: "Zeta")
    d = create_check(name: "a lone site")
    c.update_columns(status: "down")

    assert_equal [ c, b, a, d ], Check.in_overview_order(Check.all.to_a)
  end
end
