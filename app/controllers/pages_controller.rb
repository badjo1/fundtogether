class PagesController < ApplicationController
  allow_unauthenticated_access only: %i[ home ]

  def home
  end

  def dashboard
    @account = current_account

    redirect_to(new_account_path, alert: "Maak eerst een account aan om te beginnen") and return unless @account

    # Stats
    @total_balance = @account.total_balance_euros
    @user_balance = @account.user_balance(current_user)
    @members_count = @account.active_members_count
    @monthly_expenses = @account.monthly_expenses_euros

    # Recent transactions
    @recent_transactions = @account.recent_transactions(5)
  end
end
