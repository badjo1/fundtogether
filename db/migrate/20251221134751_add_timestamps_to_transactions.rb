class AddTimestampsToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :created_at, :datetime
    add_column :transactions, :updated_at, :datetime

    # Backfill existing records
    reversible do |dir|
      dir.up do
        execute "UPDATE transactions SET created_at = NOW(), updated_at = NOW() WHERE created_at IS NULL"
      end
    end

    change_column_null :transactions, :created_at, false
    change_column_null :transactions, :updated_at, false
  end
end
