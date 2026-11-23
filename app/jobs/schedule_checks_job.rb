# Runs every minute (config/recurring.yml) and queues every check that's due.
class ScheduleChecksJob < ApplicationJob
  # If the scheduler hasn't run for this long, the overview and board say
  # checking has stopped instead of showing old results as current.
  STALLED_AFTER = 3.minutes

  def perform(now = Time.current)
    Setting.tick!(now)

    Check.due(now).find_each do |check|
      # Set the next run now, so a lost job (a restart mid-check) doesn't stop
      # the website from being checked again.
      check.update_column(:next_check_at, now + check.interval)
      RunCheckJob.perform_later(check)
    end
  end
end
