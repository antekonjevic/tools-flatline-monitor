class CreateCheckResults < ActiveRecord::Migration[8.1]
  def change
    create_table :check_results do |t|
      t.references :check, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.datetime :checked_at, null: false
      t.string :outcome, null: false
      t.string :message
      t.integer :response_ms
      t.integer :http_status
    end

    add_index :check_results, [ :check_id, :checked_at ]
    add_index :check_results, :checked_at
  end
end
