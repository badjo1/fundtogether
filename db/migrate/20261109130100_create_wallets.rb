class CreateWallets < ActiveRecord::Migration[8.1]
  def change
    create_table :wallets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :address, null: false
      t.string :kind, null: false, default: "eoa"
      t.string :label
      t.datetime :verified_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :wallets, :address, unique: true, where: "revoked_at IS NULL", name: "index_wallets_on_active_address"
    add_index :wallets, :address, name: "index_wallets_on_address"
    add_check_constraint :wallets, "address ~ '^0x[0-9a-f]{40}$'", name: "wallets_address_lowercase"
    add_check_constraint :wallets, "kind IN ('eoa')", name: "wallets_kind"

    create_table :wallet_challenges do |t|
      t.references :user, null: false, foreign_key: true
      t.references :session, null: false, foreign_key: { on_delete: :cascade }
      t.string :nonce, null: false
      t.string :purpose, null: false
      t.string :address
      t.bigint :chain_id
      t.text :message
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end

    add_index :wallet_challenges, :nonce, unique: true
    add_index :wallet_challenges, :expires_at
    add_check_constraint :wallet_challenges, "purpose IN ('link', 'handoff')", name: "wallet_challenges_purpose"
    add_check_constraint :wallet_challenges, "address IS NULL OR address ~ '^0x[0-9a-f]{40}$'",
                         name: "wallet_challenges_address_lowercase"
    add_check_constraint :wallet_challenges,
                         "purpose <> 'link' OR (address IS NOT NULL AND message IS NOT NULL AND chain_id IS NOT NULL)",
                         name: "wallet_challenges_link_complete"
  end
end
