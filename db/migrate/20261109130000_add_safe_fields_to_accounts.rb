class AddSafeFieldsToAccounts < ActiveRecord::Migration[8.1]
  def change
    change_table :accounts, bulk: true do |t|
      t.bigint :chain_id
      t.string :token_address
      t.string :safe_address
      t.decimal :safe_salt_nonce, precision: 78, scale: 0
      t.string :safe_status, null: false, default: "draft"
      t.string :deploy_tx_hash
      t.bigint :synced_block
      t.string :synced_block_hash
      t.datetime :synced_at
      t.uuid :safe_group_uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :safe_owners, array: true, null: false, default: []
      t.integer :safe_threshold
      t.string :safe_verification_error
      t.datetime :safe_verified_at
      t.decimal :balance_cached, precision: 78, scale: 0
      t.datetime :balance_cached_at
    end

    add_index :accounts, [ :chain_id, :safe_address ], unique: true, where: "safe_address IS NOT NULL"

    add_check_constraint :accounts, "safe_status IN ('draft', 'deploying', 'active')", name: "accounts_safe_status"
    add_check_constraint :accounts, "token_address IS NULL OR token_address ~ '^0x[0-9a-f]{40}$'",
                         name: "accounts_token_address_lowercase"
    add_check_constraint :accounts, "safe_address IS NULL OR safe_address ~ '^0x[0-9a-f]{40}$'",
                         name: "accounts_safe_address_lowercase"
    add_check_constraint :accounts, "deploy_tx_hash IS NULL OR deploy_tx_hash ~ '^0x[0-9a-f]{64}$'",
                         name: "accounts_deploy_tx_hash_lowercase"
    add_check_constraint :accounts, "synced_block_hash IS NULL OR synced_block_hash ~ '^0x[0-9a-f]{64}$'",
                         name: "accounts_synced_block_hash_lowercase"
    add_check_constraint :accounts,
                         "safe_status = 'draft' OR (chain_id IS NOT NULL AND token_address IS NOT NULL AND " \
                         "safe_address IS NOT NULL AND safe_salt_nonce IS NOT NULL AND safe_threshold IS NOT NULL)",
                         name: "accounts_safe_configured_unless_draft"
  end
end
