class AddVerificationBackoffToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :safe_verification_attempts, :integer, null: false, default: 0
    add_column :accounts, :safe_verification_next_at, :datetime
  end
end
