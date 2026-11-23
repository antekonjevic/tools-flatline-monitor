class DownPeriod < ApplicationRecord
  belongs_to :check

  scope :ongoing, -> { where(ended_at: nil) }
  scope :recent_first, -> { order(started_at: :desc) }

  def ongoing?
    ended_at.nil?
  end

  def duration(now = Time.current)
    (ended_at || now) - started_at
  end
end
