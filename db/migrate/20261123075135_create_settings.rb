class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :board_token, null: false
      # Set while Flatline can't reach the internet itself.
      t.datetime :offline_since
      # Last time the scheduler ran, so stalled checking is visible.
      t.datetime :last_tick_at
      t.timestamps
    end
  end
end
