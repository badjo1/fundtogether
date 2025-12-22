class UsersController < ApplicationController
  def index
    @account = current_account
    redirect_to(new_account_path, alert: "Maak eerst een account aan om te beginnen") and return unless @account

    @users = @account.active_users.includes(:account_memberships)
    @pending_invitations = @account.invitations.where(status: 'pending')

    # Stats
    @total_members = @users.count
    @active_members = @users.count # All loaded users are active
    @average_balance = @users.any? ? @account.total_balance_euros / @users.count : 0
  end
end
