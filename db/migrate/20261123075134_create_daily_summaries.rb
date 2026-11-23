class CreateDailySummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_summaries do |t|
      t.references :check, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :day, null: false
      # Seconds the website was watched (not paused, Flatline online), and how
      # many of those it was down.
      t.integer :monitored_seconds, null: false, default: 0
      t.integer :down_seconds, null: false, default: 0
      t.integer :checks_count, null: false, default: 0
      t.integer :warnings_count, null: false, default: 0
    end

    add_index :daily_summaries, [ :check_id, :day ], unique: true
    add_index :daily_summaries, :day
  end
end
