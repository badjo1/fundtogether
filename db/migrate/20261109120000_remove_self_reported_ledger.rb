# The self-reported ledger never represented money. On-chain figures come from
# chain data (docs/ARCHITECTURE.md). Rolling back restores the structure, not the data.
class RemoveSelfReportedLedger < ActiveRecord::Migration[8.1]
  def change
    drop_table :transactions do |t|
      t.bigint :account_id, null: false
      t.integer :amount_cents, default: 0, null: false
      t.string :description
      t.bigint :from_user_id, null: false
      t.string :status
      t.bigint :to_user_id
      t.string :token
      t.string :transaction_type
      t.string :tx_hash
      t.timestamps
      t.index :account_id
      t.index :from_user_id
      t.index :to_user_id
      t.index :tx_hash, unique: true
    end

    remove_column :account_memberships, :balance_cents, :integer, default: 0, null: false
    remove_column :accounts, :split_method, :string, default: "equal", null: false
    remove_column :accounts, :wallet_address, :string
    remove_index :users, :wallet_address, unique: true
    remove_column :users, :wallet_address, :string
  end
end
