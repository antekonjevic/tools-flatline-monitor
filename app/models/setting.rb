# The single row of app-wide state: the board's secret token, whether Flatline
# itself is offline, and when the scheduler last ran.
class Setting < ApplicationRecord
  has_secure_token :board_token, length: 32

  def self.instance
    first || create!
  end

  def self.board_token_matches?(token)
    token.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, instance.board_token)
  end

  def self.mark_offline!(at = Time.current)
    setting = instance
    setting.update!(offline_since: at) unless setting.offline?
  end

  def self.mark_online!
    where.not(offline_since: nil).update_all(offline_since: nil, updated_at: Time.current)
  end

  def self.tick!(at = Time.current)
    instance.update_columns(last_tick_at: at, updated_at: at)
  end

  def offline?
    offline_since.present?
  end

  # True when the scheduler has stopped, so the results on screen are old.
  def checking_stalled?(now = Time.current)
    return false unless Check.active.exists?

    last_tick_at.nil? || last_tick_at < now - ScheduleChecksJob::STALLED_AFTER
  end
end
