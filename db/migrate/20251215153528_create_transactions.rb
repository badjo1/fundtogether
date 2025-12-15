class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :from_user, null: false, foreign_key: { to_table: :users }
      t.references :to_user,   null: false, foreign_key: { to_table: :users }
      t.integer :amount_cents, default: 0, null: false
      t.string :description
      t.string :tx_hash
      t.string :status
      t.string :transaction_type
      t.string :token
    end
    add_index :transactions, :tx_hash, unique: true
  end
end

