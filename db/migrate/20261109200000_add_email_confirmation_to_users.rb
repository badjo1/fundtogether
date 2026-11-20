# Unconfirmed until proven: existing rows stay NULL on purpose. There is no production data, and a
# pre-registered address must not be grandfathered in as confirmed (docs/SECURITY_REVIEW.md, H2).
class AddEmailConfirmationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_confirmed_at, :datetime
    add_column :users, :email_confirmation_sent_at, :datetime
  end
end
