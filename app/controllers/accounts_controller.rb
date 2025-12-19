class AccountsController < ApplicationController
  before_action :set_account, only: [:show, :edit, :update, :destroy, :switch, :leave]

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
      @account.account_memberships.create!(user: current_user, role: :admin)
      current_user.update(current_account: @account)
      redirect_to dashboard_path, notice: "Account succesvol aangemaakt"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @account.update(account_params)
      redirect_to settings_path, notice: "Account instellingen bijgewerkt"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize_admin!
    
    account_name = @account.name
    
    User.where(current_account: @account).update_all(current_account_id: nil)
    if @account.destroy
      # Als dit de huidige account was, switch naar een andere
      if current_user.current_account == @account || current_user.current_account.nil?
        other_account = current_user.accounts.first
        current_user.update(current_account: other_account)
      end
      
      redirect_to dashboard_path, notice: "Account '#{account_name}' is succesvol verwijderd"
    else
      redirect_to settings_path, alert: "Kon account niet verwijderen: #{@account.errors.full_messages.join(', ')}"
    end
  end

  def switch
    if current_user.accounts.include?(@account)
      current_user.update(current_account: @account)
      redirect_to dashboard_path, notice: "Gewisseld naar #{@account.name}"
    else
      redirect_to dashboard_path, alert: "Je hebt geen toegang tot dit account"
    end
  end

  def leave
    membership = @account.account_memberships.find_by(user: current_user)
    
    if membership.nil?
      redirect_to dashboard_path, alert: "Je bent geen lid van dit account"
      return
    end

    # Controleer of dit de laatste admin is
    if membership.admin? && @account.admins.count == 1
      redirect_to settings_path, alert: "Je kunt niet vertrekken als enige admin. Maak eerst iemand anders admin of verwijder het account."
      return
    end

    membership.destroy
    
    # Als dit de huidige account was, switch naar een andere
    if current_user.current_account == @account
      other_account = current_user.accounts.first
      current_user.update(current_account: other_account)
    end

    redirect_to dashboard_path, notice: "Je hebt het account '#{@account.name}' verlaten"
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def account_params
    params.require(:account).permit(:name, :description)
  end

  def authorize_admin!
    unless current_account_membership&.admin?
      redirect_to settings_path, alert: "Alleen admins kunnen het account verwijderen"
    end
  end

  def current_account_membership
    @account.account_memberships.find_by(user: current_user)
  end
end