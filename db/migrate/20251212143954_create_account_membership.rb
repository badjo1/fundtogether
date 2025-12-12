class CreateAccountMembership < ActiveRecord::Migration[8.1]
  def change
    create_table :account_memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string "role", default: "member", null: false
      t.integer :balance_cents, default: 0, null: false
      t.datetime "joined_at"
      t.boolean "active", default: true
      t.timestamps
    end
    add_index :account_memberships, [:account_id, :user_id], unique: true
    add_index :account_memberships, [:user_id, :active]
    add_index :account_memberships, [:role]
  end
end