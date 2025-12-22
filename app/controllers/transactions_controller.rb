class TransactionsController < ApplicationController
  before_action :set_account

  def index
    @transactions = @account.transactions.includes(:from_user, :to_user).recent

    # Apply filters
    @transactions = @transactions.where(transaction_type: params[:type]) if params[:type].present?
    @transactions = @transactions.where(status: params[:status]) if params[:status].present?
    @transactions = @transactions.where(token: params[:token]) if params[:token].present?
  end

  def new
    @transaction = @account.transactions.build
    @transaction_type = params[:type] || "deposit"

    unless %w[deposit expense].include?(@transaction_type)
      redirect_to dashboard_path, alert: "Ongeldig transactietype"
    end
  end

  def create
    @transaction = @account.transactions.build(transaction_params)
    @transaction.from_user = current_user
    @transaction.status = "confirmed"

    if @transaction.save
      flash_message = @transaction.deposit? ? "Storting succesvol toegevoegd" : "Uitgave succesvol toegevoegd"
      redirect_to dashboard_path, notice: flash_message
    else
      @transaction_type = @transaction.transaction_type
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = current_account

    redirect_to(new_account_path, alert: "Maak eerst een account aan") unless @account
  end

  def transaction_params
    params.require(:transaction).permit(:amount_euros, :description, :transaction_type, :token)
  end
end
