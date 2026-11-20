class CreateSafeProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :safe_proposals do |t|
      t.references :account, null: false, foreign_key: true
      t.references :proposer, null: false, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.string :title, null: false
      t.jsonb :params, null: false, default: {}
      t.string :to, null: false
      t.decimal :value, precision: 78, scale: 0, null: false, default: 0
      t.text :data, null: false, default: "0x"
      t.integer :operation, null: false, default: 0
      t.decimal :nonce, precision: 78, scale: 0, null: false
      t.string :safe_tx_hash, null: false
      t.string :state, null: false, default: "open"
      t.string :execution_tx_hash
      t.datetime :executed_at
      t.timestamps
    end

    add_index :safe_proposals, [ :account_id, :safe_tx_hash ], unique: true
    add_index :safe_proposals, [ :account_id, :state, :nonce ]
    add_check_constraint :safe_proposals,
                         "kind IN ('transfer_token', 'transfer_native', 'add_owner', 'remove_owner', 'swap_owner', " \
                         "'change_threshold', 'rejection')",
                         name: "safe_proposals_kind"
    add_check_constraint :safe_proposals, "state IN ('open', 'executed', 'failed', 'superseded')",
                         name: "safe_proposals_state"
    add_check_constraint :safe_proposals, "operation = 0", name: "safe_proposals_operation_call"
    add_check_constraint :safe_proposals, "\"to\" ~ '^0x[0-9a-f]{40}$'", name: "safe_proposals_to_lowercase"
    add_check_constraint :safe_proposals, "data ~ '^0x([0-9a-f]{2})*$'", name: "safe_proposals_data_lowercase"
    add_check_constraint :safe_proposals, "safe_tx_hash ~ '^0x[0-9a-f]{64}$'", name: "safe_proposals_hash_lowercase"
    add_check_constraint :safe_proposals, "value >= 0 AND nonce >= 0", name: "safe_proposals_non_negative"
    add_check_constraint :safe_proposals, "execution_tx_hash IS NULL OR execution_tx_hash ~ '^0x[0-9a-f]{64}$'",
                         name: "safe_proposals_execution_hash_lowercase"

    create_table :safe_signatures do |t|
      t.references :safe_proposal, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :signer_address, null: false
      t.string :signature, null: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :safe_signatures, [ :safe_proposal_id, :signer_address ], unique: true
    add_check_constraint :safe_signatures, "signer_address ~ '^0x[0-9a-f]{40}$'", name: "safe_signatures_signer_lowercase"
    add_check_constraint :safe_signatures, "signature ~ '^0x[0-9a-f]{128}(1b|1c)$'", name: "safe_signatures_canonical"
  end
end
