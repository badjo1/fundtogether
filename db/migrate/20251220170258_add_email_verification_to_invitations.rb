class AddEmailVerificationToInvitations < ActiveRecord::Migration[8.1]
  def up
    # Maak email nullable (was NOT NULL)
    change_column_null :invitations, :email, true

    # Email verificatie tracking
    add_column :invitations, :email_verified_at, :datetime
    add_column :invitations, :email_verification_token, :string
    add_column :invitations, :email_verification_sent_at, :datetime

    # Optioneel: verrijk uitnodiging later met naam
    add_column :invitations, :invitee_name, :string

    # Index voor snelle token lookups
    add_index :invitations, :email_verification_token, unique: true

    # Backwards compatibility: Auto-verify alle bestaande invitations met email
    Invitation.where(email_verified_at: nil)
              .where.not(email: nil)
              .update_all(email_verified_at: Time.current)
  end

  def down
    remove_index :invitations, :email_verification_token
    remove_column :invitations, :invitee_name
    remove_column :invitations, :email_verification_sent_at
    remove_column :invitations, :email_verification_token
    remove_column :invitations, :email_verified_at
    change_column_null :invitations, :email, false
  end
end
