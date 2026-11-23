class CreateDownPeriods < ActiveRecord::Migration[8.1]
  def change
    create_table :down_periods do |t|
      t.references :check, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.string :reason
    end

    add_index :down_periods, [ :check_id, :started_at ]
    add_index :down_periods, :ended_at
  end
end
