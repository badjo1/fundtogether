class MakeToUserIdOptionalInTransactions < ActiveRecord::Migration[8.1]
  def change
    # Remove foreign key constraint
    remove_foreign_key :transactions, column: :to_user_id
    # Make nullable
    change_column_null :transactions, :to_user_id, true
    # Re-add foreign key with optional
    add_foreign_key :transactions, :users, column: :to_user_id
  end
end
