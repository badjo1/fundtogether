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

ActiveRecord::Schema[8.1].define(version: 2025_12_15_154815) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "active", default: true
    t.integer "balance_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "joined_at"
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "user_id"], name: "index_account_memberships_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_account_memberships_on_account_id"
    t.index ["role"], name: "index_account_memberships_on_role"
    t.index ["user_id", "active"], name: "index_account_memberships_on_user_id_and_active"
    t.index ["user_id"], name: "index_account_memberships_on_user_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "split_method", default: "equal", null: false
    t.datetime "updated_at", null: false
    t.string "wallet_address"
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "invited_by_id", null: false
    t.string "status"
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "description"
    t.bigint "from_user_id", null: false
    t.string "status"
    t.bigint "to_user_id", null: false
    t.string "token"
    t.string "transaction_type"
    t.string "tx_hash"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["from_user_id"], name: "index_transactions_on_from_user_id"
    t.index ["to_user_id"], name: "index_transactions_on_to_user_id"
    t.index ["tx_hash"], name: "index_transactions_on_tx_hash", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_account_id"
    t.string "email_address", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "wallet_address"
    t.index ["current_account_id"], name: "index_users_on_current_account_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["wallet_address"], name: "index_users_on_wallet_address", unique: true
  end

  add_foreign_key "account_memberships", "accounts"
  add_foreign_key "account_memberships", "users"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "users", column: "from_user_id"
  add_foreign_key "transactions", "users", column: "to_user_id"
  add_foreign_key "users", "accounts", column: "current_account_id"
end
