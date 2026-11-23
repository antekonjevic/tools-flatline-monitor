require "test_helper"

class ScheduleChecksJobTest < ActiveJob::TestCase
  setup { travel_to Time.zone.local(2026, 11, 20, 12, 0, 0) }

  test "queues checks that are due and sets their next run" do
    due = create_check(name: "due")
    due.update_columns(next_check_at: 10.seconds.from_now)
    later = create_check(name: "later")
    later.update_columns(next_check_at: 3.minutes.from_now)
    paused = create_check(name: "paused")
    paused.pause!
    paused.update_columns(next_check_at: 1.minute.ago)

    ScheduleChecksJob.perform_now

    assert_enqueued_jobs 1, only: RunCheckJob
    assert_enqueued_with job: RunCheckJob, args: [ due ]
    assert_equal Time.current + 5.minutes, due.reload.next_check_at
    assert_equal Time.current, Setting.instance.last_tick_at
  end

  test "a recheck one minute after a failure is picked up by the next tick" do
    check = create_check
    check.update_columns(next_check_at: Time.current + 1.minute + 5.seconds)

    travel 1.minute
    ScheduleChecksJob.perform_now

    assert_enqueued_with job: RunCheckJob, args: [ check ]
  end
end
