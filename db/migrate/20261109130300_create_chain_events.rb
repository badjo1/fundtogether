class CreateChainEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :chain_events do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.bigint :chain_id, null: false
      t.string :tx_hash, null: false
      t.integer :log_index, null: false
      t.bigint :block_number, null: false
      t.string :block_hash, null: false
      t.string :kind, null: false
      t.string :from_address
      t.string :to_address
      t.string :token_address
      t.decimal :amount, precision: 78, scale: 0
      t.string :safe_tx_hash
      t.datetime :occurred_at, null: false
      t.boolean :finalized, null: false, default: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :safe_proposal, foreign_key: { on_delete: :nullify }
      t.timestamps
    end

    # Includes account_id: a Transfer between two FundTogether Safes is one log and belongs
    # to both funds.
    add_index :chain_events, [ :account_id, :chain_id, :tx_hash, :log_index ], unique: true,
              name: "index_chain_events_uniqueness"
    add_index :chain_events, [ :account_id, :block_number ]
    add_index :chain_events, [ :account_id, :finalized ]
    add_index :chain_events, [ :account_id, :safe_tx_hash ]
    add_check_constraint :chain_events,
                         "kind IN ('token_in', 'token_out', 'native_in', 'execution_success', 'execution_failure', " \
                         "'owner_added', 'owner_removed', 'threshold_changed')",
                         name: "chain_events_kind"
    add_check_constraint :chain_events, "tx_hash ~ '^0x[0-9a-f]{64}$' AND block_hash ~ '^0x[0-9a-f]{64}$'",
                         name: "chain_events_hashes_lowercase"
    add_check_constraint :chain_events, "safe_tx_hash IS NULL OR safe_tx_hash ~ '^0x[0-9a-f]{64}$'",
                         name: "chain_events_safe_tx_hash_lowercase"
    add_check_constraint :chain_events, "from_address IS NULL OR from_address ~ '^0x[0-9a-f]{40}$'",
                         name: "chain_events_from_lowercase"
    add_check_constraint :chain_events, "to_address IS NULL OR to_address ~ '^0x[0-9a-f]{40}$'",
                         name: "chain_events_to_lowercase"
    add_check_constraint :chain_events, "token_address IS NULL OR token_address ~ '^0x[0-9a-f]{40}$'",
                         name: "chain_events_token_lowercase"
    add_check_constraint :chain_events, "amount IS NULL OR amount >= 0", name: "chain_events_amount_non_negative"
  end
end
