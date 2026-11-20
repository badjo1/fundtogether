# A proposal can be withdrawn off-chain. The state joins the check constraint, and a cancelled row no
# longer blocks an identical new proposal at the same nonce (same safeTxHash).
class AddCancellationToSafeProposals < ActiveRecord::Migration[8.1]
  def up
    add_column :safe_proposals, :cancelled_at, :datetime
    add_reference :safe_proposals, :cancelled_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false

    remove_check_constraint :safe_proposals, name: "safe_proposals_state"
    add_check_constraint :safe_proposals, "state::text = ANY (ARRAY['open'::character varying, 'executed'::character varying, 'failed'::character varying, 'superseded'::character varying, 'cancelled'::character varying]::text[])", name: "safe_proposals_state"

    remove_index :safe_proposals, column: [ :account_id, :safe_tx_hash ]
    add_index :safe_proposals, [ :account_id, :safe_tx_hash ], unique: true, where: "state <> 'cancelled'",
              name: "index_safe_proposals_on_account_id_and_live_safe_tx_hash"
    add_index :safe_proposals, [ :account_id, :safe_tx_hash ], name: "index_safe_proposals_on_account_id_and_safe_tx_hash"
    add_index :safe_proposals, [ :account_id, :proposer_id, :state ], name: "index_safe_proposals_on_account_proposer_state"
  end

  def down
    remove_index :safe_proposals, name: "index_safe_proposals_on_account_proposer_state"
    remove_index :safe_proposals, name: "index_safe_proposals_on_account_id_and_safe_tx_hash"
    remove_index :safe_proposals, name: "index_safe_proposals_on_account_id_and_live_safe_tx_hash"
    execute "DELETE FROM safe_proposals WHERE state = 'cancelled'"
    add_index :safe_proposals, [ :account_id, :safe_tx_hash ], unique: true, name: "index_safe_proposals_on_account_id_and_safe_tx_hash"
    remove_check_constraint :safe_proposals, name: "safe_proposals_state"
    add_check_constraint :safe_proposals, "state::text = ANY (ARRAY['open'::character varying, 'executed'::character varying, 'failed'::character varying, 'superseded'::character varying]::text[])", name: "safe_proposals_state"
    remove_reference :safe_proposals, :cancelled_by
    remove_column :safe_proposals, :cancelled_at
  end
end
