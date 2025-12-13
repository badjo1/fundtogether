class AccountsController < ApplicationController
  before_action :set_account, only: [:show, :edit, :update, :destroy, :switch]

  def index
    @accounts = current_user.accounts
  end

  def show
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      # Voeg de huidige gebruiker toe als admin
      @account.add_member(current_user, role: 'admin')
      
      # Stel deze account in als huidige account
      current_user.update(current_account: @account)

      redirect_to dashboard_path, notice: "Account '#{@account.name}' is succesvol aangemaakt!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @account.update(account_params)
      redirect_to settings_path, notice: "Account is bijgewerkt."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account.destroy
    current_user.ensure_current_account
    redirect_to dashboard_path, notice: "Account is verwijderd."
  end

  def switch
    if current_user.switch_to_account(@account)
      redirect_to dashboard_path, notice: "Gewisseld naar '#{@account.name}'."
    else
      redirect_to dashboard_path, alert: "Kon niet wisselen naar deze account."
    end
  end

  private

  def set_account
    @account = current_user.accounts.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Account niet gevonden."
  end

  def account_params
    params.require(:account).permit(:name, :description, :split_method, :min_deposit, :auto_convert, :notifications)
  end

end