# Nightly: forget check results and down periods older than six months.
class PruneHistoryJob < ApplicationJob
  def perform(now = Time.current)
    cutoff = now - Check::HISTORY

    CheckResult.where(checked_at: ...cutoff).in_batches(of: 10_000).delete_all
    DownPeriod.where(ended_at: ...cutoff).in_batches(of: 10_000).delete_all
    DailySummary.where(day: ...cutoff.to_date).in_batches(of: 10_000).delete_all
  end
end
