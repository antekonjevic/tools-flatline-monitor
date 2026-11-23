require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "short durations" do
    assert_equal "45 s", short_duration(45)
    assert_equal "12 min", short_duration(12.minutes)
    assert_equal "2 h 14 min", short_duration(2.hours + 14.minutes)
    assert_equal "3 h", short_duration(3.hours)
    assert_equal "3 d 4 h", short_duration(3.days + 4.hours)
  end

  test "uptime never rounds up to 100%" do
    assert_equal "100%", uptime_text(1.0)
    assert_equal "99.99%", uptime_text(0.99999)
    assert_equal "97.50%", uptime_text(0.975)
    assert_equal "—", uptime_text(nil)
  end
end
