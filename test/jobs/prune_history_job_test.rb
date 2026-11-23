require "test_helper"

class PruneHistoryJobTest < ActiveJob::TestCase
  test "deletes results and down periods older than six months" do
    check = create_check
    old = check.results.create!(checked_at: 7.months.ago, outcome: "up")
    recent = check.results.create!(checked_at: 5.months.ago, outcome: "up")
    old_period = check.down_periods.create!(started_at: 7.months.ago, ended_at: 7.months.ago + 1.hour)
    ongoing = check.down_periods.create!(started_at: 8.months.ago)

    PruneHistoryJob.perform_now

    assert_not CheckResult.exists?(old.id)
    assert CheckResult.exists?(recent.id)
    assert_not DownPeriod.exists?(old_period.id)
    assert DownPeriod.exists?(ongoing.id)
  end
end
