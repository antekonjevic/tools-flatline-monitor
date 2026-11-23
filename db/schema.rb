# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_23_075135) do
  create_table "check_results", force: :cascade do |t|
    t.integer "check_id", null: false
    t.datetime "checked_at", null: false
    t.string "outcome", null: false
    t.string "message"
    t.integer "response_ms"
    t.integer "http_status"
    t.index ["check_id", "checked_at"], name: "index_check_results_on_check_id_and_checked_at"
    t.index ["checked_at"], name: "index_check_results_on_checked_at"
  end

  create_table "checks", force: :cascade do |t|
    t.string "name", null: false
    t.string "url", null: false
    t.string "group_name"
    t.integer "interval_minutes", default: 5, null: false
    t.string "required_phrase"
    t.integer "failure_threshold", default: 2, null: false
    t.string "status", default: "pending", null: false
    t.datetime "status_changed_at"
    t.datetime "paused_at"
    t.datetime "next_check_at"
    t.datetime "last_checked_at"
    t.string "last_message"
    t.integer "last_response_ms"
    t.integer "last_http_status"
    t.datetime "cert_expires_at"
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "failing_since"
    t.datetime "accounted_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["next_check_at"], name: "index_checks_on_next_check_at"
    t.index ["status"], name: "index_checks_on_status"
  end

  create_table "daily_summaries", force: :cascade do |t|
    t.integer "check_id", null: false
    t.date "day", null: false
    t.integer "monitored_seconds", default: 0, null: false
    t.integer "down_seconds", default: 0, null: false
    t.integer "checks_count", default: 0, null: false
    t.integer "warnings_count", default: 0, null: false
    t.index ["check_id", "day"], name: "index_daily_summaries_on_check_id_and_day", unique: true
    t.index ["day"], name: "index_daily_summaries_on_day"
  end

  create_table "down_periods", force: :cascade do |t|
    t.integer "check_id", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.string "reason"
    t.index ["check_id", "started_at"], name: "index_down_periods_on_check_id_and_started_at"
    t.index ["ended_at"], name: "index_down_periods_on_ended_at"
  end

  create_table "settings", force: :cascade do |t|
    t.string "board_token", null: false
    t.datetime "offline_since"
    t.datetime "last_tick_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "check_results", "checks", on_delete: :cascade
  add_foreign_key "daily_summaries", "checks", on_delete: :cascade
  add_foreign_key "down_periods", "checks", on_delete: :cascade
end
