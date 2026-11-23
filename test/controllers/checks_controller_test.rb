require "test_helper"

class ChecksControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in }

  test "overview shows totals with down websites first" do
    create_check(name: "Fine site")
    down = create_check(name: "Broken site")
    down.update_columns(status: "down", status_changed_at: 1.hour.ago)
    paused = create_check(name: "Resting site")
    paused.pause!

    get root_path

    assert_response :success
    assert_select ".totals", "0 up · 1 down · 1 paused · 1 pending"
    assert_select ".check-name", count: 3
    assert_select ".check-group:first-of-type .check-name", "Broken site"
    assert_select ".last-check"
    assert_select ".bars rect", count: 3 * Check::BAR_DAYS
  end

  test "overview says when Flatline itself is offline" do
    create_check
    Setting.mark_offline!

    get root_path

    assert_select ".banner-offline"
  end

  test "overview says when checking has stopped" do
    create_check
    Setting.tick!(1.hour.ago)

    get root_path

    assert_select ".banner-stalled"
  end

  test "says plainly when no check has ever run" do
    create_check

    get root_path

    assert_select ".banner-stalled", /No checks have run/
  end

  test "adds a website and starts checking it" do
    assert_enqueued_with(job: RunCheckJob) do
      post checks_path, params: { check: { name: "Shop", url: "shop.example.com", interval_minutes: 15,
        required_phrase: "Add to cart", failure_threshold: 3, group_name: "Acme" } }
    end

    check = Check.last
    assert_redirected_to check_path(check)
    assert_equal "https://shop.example.com", check.url
    assert_equal 15, check.interval_minutes
    assert_equal 3, check.failure_threshold
    assert_equal "Acme", check.group_name
  end

  test "shows errors for an invalid website" do
    post checks_path, params: { check: { name: "", url: "nope", interval_minutes: 5, failure_threshold: 2 } }

    assert_response :unprocessable_content
    assert_select ".form-errors li", minimum: 2
  end

  test "history lists down periods and recent checks" do
    check = create_check
    check.down_periods.create!(started_at: 2.days.ago, ended_at: 2.days.ago + 14.minutes, reason: "HTTP 502 Bad Gateway")
    check.down_periods.create!(started_at: 7.months.ago, ended_at: 7.months.ago + 1.hour, reason: "Too old")
    check.results.create!(checked_at: 1.minute.ago, outcome: "up", http_status: 200, response_ms: 180)

    get check_path(check)

    assert_response :success
    assert_select "td", "HTTP 502 Bad Gateway"
    assert_select "td", text: "Too old", count: 0
    assert_select "td", "14 min"
  end

  test "editing the address checks again straight away" do
    check = create_check

    assert_enqueued_with(job: RunCheckJob) do
      patch check_path(check), params: { check: { url: "https://example.org" } }
    end
    assert_redirected_to check_path(check)
  end

  test "pauses and resumes" do
    check = create_check

    post check_pause_path(check)
    assert check.reload.paused?

    delete check_pause_path(check)
    assert check.reload.pending?
  end

  test "removes a website with its history" do
    check = create_check
    check.results.create!(checked_at: Time.current, outcome: "up")

    delete check_path(check)

    assert_redirected_to root_path
    assert_not Check.exists?(check.id)
    assert_equal 0, CheckResult.count
  end
end
