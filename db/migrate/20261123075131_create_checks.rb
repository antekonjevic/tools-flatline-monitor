class CreateChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :checks do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.string :group_name
      t.integer :interval_minutes, null: false, default: 5
      t.string :required_phrase
      t.integer :failure_threshold, null: false, default: 2

      t.string :status, null: false, default: "pending"
      t.datetime :status_changed_at
      t.datetime :paused_at

      t.datetime :next_check_at
      t.datetime :last_checked_at
      t.string :last_message
      t.integer :last_response_ms
      t.integer :last_http_status
      t.datetime :cert_expires_at

      # Failed checks in a row, and when the current run of failures began.
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :failing_since

      # Up to when this check's time has been added to its daily summaries.
      t.datetime :accounted_until

      t.timestamps
    end

    add_index :checks, :next_check_at
    add_index :checks, :status
  end
end
