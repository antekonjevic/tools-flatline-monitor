class CheckResult < ApplicationRecord
  belongs_to :check

  OUTCOMES = %w[up warning down].freeze

  validates :outcome, inclusion: { in: OUTCOMES }

  scope :recent_first, -> { order(checked_at: :desc) }
end
