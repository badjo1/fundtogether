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

ActiveRecord::Schema[8.1].define(version: 2026_11_09_200400) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "joined_at"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "index_account_memberships_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_account_memberships_on_account_id"
    t.index ["role"], name: "index_account_memberships_on_role"
    t.index ["user_id", "active"], name: "index_account_memberships_on_user_id_and_active"
    t.index ["user_id"], name: "index_account_memberships_on_user_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "chain_id"
    t.string "token_address"
    t.string "safe_address"
    t.decimal "safe_salt_nonce", precision: 78
    t.string "safe_status", default: "draft", null: false
    t.string "deploy_tx_hash"
    t.bigint "synced_block"
    t.string "synced_block_hash"
    t.datetime "synced_at"
    t.uuid "safe_group_uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "safe_owners", default: [], null: false, array: true
    t.integer "safe_threshold"
    t.string "safe_verification_error"
    t.datetime "safe_verified_at"
    t.decimal "balance_cached", precision: 78
    t.datetime "balance_cached_at"
    t.integer "safe_verification_attempts", default: 0, null: false
    t.datetime "safe_verification_next_at"
    t.index ["chain_id", "safe_address"], name: "index_accounts_on_chain_id_and_safe_address", unique: true, where: "(safe_address IS NOT NULL)"
    t.check_constraint "deploy_tx_hash IS NULL OR deploy_tx_hash::text ~ '^0x[0-9a-f]{64}$'::text", name: "accounts_deploy_tx_hash_lowercase"
    t.check_constraint "safe_address IS NULL OR safe_address::text ~ '^0x[0-9a-f]{40}$'::text", name: "accounts_safe_address_lowercase"
    t.check_constraint "safe_status::text = 'draft'::text OR chain_id IS NOT NULL AND token_address IS NOT NULL AND safe_address IS NOT NULL AND safe_salt_nonce IS NOT NULL AND safe_threshold IS NOT NULL", name: "accounts_safe_configured_unless_draft"
    t.check_constraint "safe_status::text = ANY (ARRAY['draft'::character varying, 'deploying'::character varying, 'active'::character varying]::text[])", name: "accounts_safe_status"
    t.check_constraint "synced_block_hash IS NULL OR synced_block_hash::text ~ '^0x[0-9a-f]{64}$'::text", name: "accounts_synced_block_hash_lowercase"
    t.check_constraint "token_address IS NULL OR token_address::text ~ '^0x[0-9a-f]{40}$'::text", name: "accounts_token_address_lowercase"
  end

  create_table "chain_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "chain_id", null: false
    t.string "tx_hash", null: false
    t.integer "log_index", null: false
    t.bigint "block_number", null: false
    t.string "block_hash", null: false
    t.string "kind", null: false
    t.string "from_address"
    t.string "to_address"
    t.string "token_address"
    t.decimal "amount", precision: 78
    t.string "safe_tx_hash"
    t.datetime "occurred_at", null: false
    t.boolean "finalized", default: false, null: false
    t.bigint "user_id"
    t.bigint "safe_proposal_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "block_number"], name: "index_chain_events_on_account_id_and_block_number"
    t.index ["account_id", "chain_id", "tx_hash", "log_index"], name: "index_chain_events_uniqueness", unique: true
    t.index ["account_id", "finalized"], name: "index_chain_events_on_account_id_and_finalized"
    t.index ["account_id", "safe_tx_hash"], name: "index_chain_events_on_account_id_and_safe_tx_hash"
    t.index ["safe_proposal_id"], name: "index_chain_events_on_safe_proposal_id"
    t.index ["user_id"], name: "index_chain_events_on_user_id"
    t.check_constraint "amount IS NULL OR amount >= 0::numeric", name: "chain_events_amount_non_negative"
    t.check_constraint "from_address IS NULL OR from_address::text ~ '^0x[0-9a-f]{40}$'::text", name: "chain_events_from_lowercase"
    t.check_constraint "kind::text = ANY (ARRAY['token_in'::character varying, 'token_out'::character varying, 'native_in'::character varying, 'execution_success'::character varying, 'execution_failure'::character varying, 'owner_added'::character varying, 'owner_removed'::character varying, 'threshold_changed'::character varying]::text[])", name: "chain_events_kind"
    t.check_constraint "safe_tx_hash IS NULL OR safe_tx_hash::text ~ '^0x[0-9a-f]{64}$'::text", name: "chain_events_safe_tx_hash_lowercase"
    t.check_constraint "to_address IS NULL OR to_address::text ~ '^0x[0-9a-f]{40}$'::text", name: "chain_events_to_lowercase"
    t.check_constraint "token_address IS NULL OR token_address::text ~ '^0x[0-9a-f]{40}$'::text", name: "chain_events_token_lowercase"
    t.check_constraint "tx_hash::text ~ '^0x[0-9a-f]{64}$'::text AND block_hash::text ~ '^0x[0-9a-f]{64}$'::text", name: "chain_events_hashes_lowercase"
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "invited_by_id", null: false
    t.string "email"
    t.string "status"
    t.string "token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "email_verified_at"
    t.string "email_verification_token"
    t.datetime "email_verification_sent_at"
    t.string "invitee_name"
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["email_verification_token"], name: "index_invitations_on_email_verification_token", unique: true
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
  end

  create_table "safe_proposals", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "proposer_id", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.jsonb "params", default: {}, null: false
    t.string "to", null: false
    t.decimal "value", precision: 78, default: "0", null: false
    t.text "data", default: "0x", null: false
    t.integer "operation", default: 0, null: false
    t.decimal "nonce", precision: 78, null: false
    t.string "safe_tx_hash", null: false
    t.string "state", default: "open", null: false
    t.string "execution_tx_hash"
    t.datetime "executed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "cancelled_at"
    t.bigint "cancelled_by_id"
    t.index ["account_id", "proposer_id", "state"], name: "index_safe_proposals_on_account_proposer_state"
    t.index ["account_id", "safe_tx_hash"], name: "index_safe_proposals_on_account_id_and_live_safe_tx_hash", unique: true, where: "((state)::text <> 'cancelled'::text)"
    t.index ["account_id", "safe_tx_hash"], name: "index_safe_proposals_on_account_id_and_safe_tx_hash"
    t.index ["account_id", "state", "nonce"], name: "index_safe_proposals_on_account_id_and_state_and_nonce"
    t.index ["account_id"], name: "index_safe_proposals_on_account_id"
    t.index ["proposer_id"], name: "index_safe_proposals_on_proposer_id"
    t.check_constraint "\"to\"::text ~ '^0x[0-9a-f]{40}$'::text", name: "safe_proposals_to_lowercase"
    t.check_constraint "data ~ '^0x([0-9a-f]{2})*$'::text", name: "safe_proposals_data_lowercase"
    t.check_constraint "execution_tx_hash IS NULL OR execution_tx_hash::text ~ '^0x[0-9a-f]{64}$'::text", name: "safe_proposals_execution_hash_lowercase"
    t.check_constraint "kind::text = ANY (ARRAY['transfer_token'::character varying, 'transfer_native'::character varying, 'add_owner'::character varying, 'remove_owner'::character varying, 'swap_owner'::character varying, 'change_threshold'::character varying, 'rejection'::character varying]::text[])", name: "safe_proposals_kind"
    t.check_constraint "operation = 0", name: "safe_proposals_operation_call"
    t.check_constraint "safe_tx_hash::text ~ '^0x[0-9a-f]{64}$'::text", name: "safe_proposals_hash_lowercase"
    t.check_constraint "state::text = ANY (ARRAY['open'::character varying::text, 'executed'::character varying::text, 'failed'::character varying::text, 'superseded'::character varying::text, 'cancelled'::character varying::text])", name: "safe_proposals_state"
    t.check_constraint "value >= 0::numeric AND nonce >= 0::numeric", name: "safe_proposals_non_negative"
  end

  create_table "safe_signatures", force: :cascade do |t|
    t.bigint "safe_proposal_id", null: false
    t.string "signer_address", null: false
    t.string "signature", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "verification_mac"
    t.index ["safe_proposal_id", "signer_address"], name: "index_safe_signatures_on_safe_proposal_id_and_signer_address", unique: true
    t.index ["user_id"], name: "index_safe_signatures_on_user_id"
    t.check_constraint "signature::text ~ '^0x[0-9a-f]{128}(1b|1c)$'::text", name: "safe_signatures_canonical"
    t.check_constraint "signer_address::text ~ '^0x[0-9a-f]{40}$'::text", name: "safe_signatures_signer_lowercase"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_seen_at"
    t.index ["last_seen_at"], name: "index_sessions_on_last_seen_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", null: false
    t.bigint "current_account_id"
    t.datetime "email_confirmed_at"
    t.datetime "email_confirmation_sent_at"
    t.index ["current_account_id"], name: "index_users_on_current_account_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "wallet_challenges", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "session_id", null: false
    t.string "nonce", null: false
    t.string "purpose", null: false
    t.string "address"
    t.bigint "chain_id"
    t.text "message"
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_wallet_challenges_on_expires_at"
    t.index ["nonce"], name: "index_wallet_challenges_on_nonce", unique: true
    t.index ["session_id"], name: "index_wallet_challenges_on_session_id"
    t.index ["user_id"], name: "index_wallet_challenges_on_user_id"
    t.check_constraint "address IS NULL OR address::text ~ '^0x[0-9a-f]{40}$'::text", name: "wallet_challenges_address_lowercase"
    t.check_constraint "purpose::text <> 'link'::text OR address IS NOT NULL AND message IS NOT NULL AND chain_id IS NOT NULL", name: "wallet_challenges_link_complete"
    t.check_constraint "purpose::text = ANY (ARRAY['link'::character varying, 'handoff'::character varying]::text[])", name: "wallet_challenges_purpose"
  end

  create_table "wallets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "address", null: false
    t.string "kind", default: "eoa", null: false
    t.string "label"
    t.datetime "verified_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["address"], name: "index_wallets_on_active_address", unique: true, where: "(revoked_at IS NULL)"
    t.index ["address"], name: "index_wallets_on_address"
    t.index ["user_id"], name: "index_wallets_on_user_id"
    t.check_constraint "address::text ~ '^0x[0-9a-f]{40}$'::text", name: "wallets_address_lowercase"
    t.check_constraint "kind::text = 'eoa'::text", name: "wallets_kind"
  end

  add_foreign_key "account_memberships", "accounts"
  add_foreign_key "account_memberships", "users"
  add_foreign_key "chain_events", "accounts"
  add_foreign_key "chain_events", "safe_proposals", on_delete: :nullify
  add_foreign_key "chain_events", "users", on_delete: :nullify
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "safe_proposals", "accounts"
  add_foreign_key "safe_proposals", "users", column: "cancelled_by_id", on_delete: :nullify
  add_foreign_key "safe_proposals", "users", column: "proposer_id"
  add_foreign_key "safe_signatures", "safe_proposals", on_delete: :cascade
  add_foreign_key "safe_signatures", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "accounts", column: "current_account_id"
  add_foreign_key "wallet_challenges", "sessions", on_delete: :cascade
  add_foreign_key "wallet_challenges", "users"
  add_foreign_key "wallets", "users"
end
