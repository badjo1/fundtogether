class PagesController < ApplicationController
  allow_unauthenticated_access only: %i[ home ]
  before_action :require_current_account, only: :dashboard

  def home
  end

  def dashboard
    @account = current_account
    @funds = current_user.active_accounts.order(:name).sort_by { |fund| fund.id == @account.id ? 0 : 1 }
    @members_count = @account.active_members_count
    @chain = fund_chain
    @contribution = my_contribution
    @recent_events = @account.chain_events.includes(:user, :safe_proposal, :account).recent_first.limit(5)
    @recent_events = @recent_events.without_unknown_dust(@chain) if @chain
    @members_without_wallet = members_without_wallet
    @has_wallet = current_user.wallets.active.exists?
  end

  private

  def fund_chain
    @account.chain
  rescue Chain::Registry::ChainDisabled
    nil
  end

  def my_contribution
    rows = @account.chain_events.where(kind: "token_in", user: current_user).group(:finalized).sum(:amount)
    { final: rows.fetch(true, 0).to_i, pending: rows.fetch(false, 0).to_i }
  end

  def members_without_wallet
    @account.active_users.left_joins(:wallets).group("users.id").having("COUNT(wallets.id) FILTER (WHERE wallets.revoked_at IS NULL) = 0").count.size
  end
end
