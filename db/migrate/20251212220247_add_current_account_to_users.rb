class AddCurrentAccountToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :current_account, foreign_key: { to_table: :accounts }
  end
end
