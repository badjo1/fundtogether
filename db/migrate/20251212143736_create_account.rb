class CreateAccount < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string "name", null: false
      t.text "description"
      t.string "wallet_address"
      t.string "split_method", default: "equal", null: false
      t.timestamps
    end
    add_index :users, :wallet_address, unique: true
  end
end
