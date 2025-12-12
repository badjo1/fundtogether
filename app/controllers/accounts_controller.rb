# app/controllers/accounts_controller.rb
class AccountsController < ApplicationController
  before_action :set_account, only: [:show, :edit, :update, :destroy]
  
  def index
    @accounts = Current.user.accounts
  end
  
  def show
    switch_account(@account.id)
    redirect_to dashboard_path
  end
  
  def new
    @account = Account.new
  end
  
  def create
    @account = Account.new(account_params)
    
    if @account.save
      @account.add_user(Current.user, role: 'admin')
      switch_account(@account.id)
      
      redirect_to dashboard_path, notice: 'Account succesvol aangemaakt'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def switch
    account = Current.user.accounts.find(params[:id])
    switch_account(account.id)
    redirect_to dashboard_path, notice: "Gewisseld naar #{account.name}"
  end
  
  private
  
  def set_account
    @account = Current.user.accounts.find(params[:id])
  end
  
  def account_params
    params.require(:account).permit(:name, :description, :wallet_address, :split_method, :min_deposit)
  end
end