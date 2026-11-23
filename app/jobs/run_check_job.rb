class RunCheckJob < ApplicationJob
  # Queued from inside transactions (adding, resuming, importing), so wait
  # until the change is saved before the worker can pick the job up.
  self.enqueue_after_transaction_commit = true

  # Never run the same website twice at once; a second copy is dropped.
  limits_concurrency to: 1, key: ->(check) { check }, duration: 2.minutes, on_conflict: :discard

  # The website was removed after the job was queued.
  discard_on ActiveJob::DeserializationError

  # A check interrupted by a deploy or restart is thrown away, never counted
  # as a failure: results are only written once a check has finished.
  def perform(check)
    check.run! unless check.paused?
  end
end
