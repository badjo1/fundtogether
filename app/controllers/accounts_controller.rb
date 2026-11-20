class AccountsController < ApplicationController
  FUNDS_PER_HOUR = 5
  rate_limit to: FUNDS_PER_HOUR, within: 1.hour, by: -> { current_user&.id }, only: :create,
             with: -> { redirect_to dashboard_path, alert: "Je hebt net een paar fondsen aangemaakt. Probeer het over een uur opnieuw." }

  before_action :set_account, only: [ :update, :destroy, :switch, :leave ]
  before_action :require_account_admin, only: [ :update, :destroy ]

  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)

    saved = Account.transaction do
      next false unless @account.save

      @account.account_memberships.create!(user: current_user, role: :admin)
      current_user.update!(current_account: @account)
      true
    end

    if saved
      redirect_to account_invite_path(@account), notice: "Fonds aangemaakt. Nu de groep erbij halen."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @account.update(account_params)
      redirect_to settings_path, notice: "Account instellingen bijgewerkt"
    else
      redirect_to settings_path, alert: @account.errors.full_messages.join(", ")
    end
  end

  def destroy
    account_name = @account.name

    if @account.destroy
      redirect_to dashboard_path, notice: "Account '#{account_name}' is succesvol verwijderd"
    else
      redirect_to settings_path, alert: "Kon account niet verwijderen: #{@account.errors.full_messages.join(', ')}"
    end
  end

  def switch
    current_user.update!(current_account: @account)
    redirect_to dashboard_path, notice: "Gewisseld naar #{@account.name}"
  end

  def leave
    left = @account.with_lock do
      next false if @membership.admin? && @account.admins.count == 1

      @membership.destroy!
      Chain::ProposalCancellation.for_departed(@account, current_user, by: current_user)
      current_user.update!(current_account: current_user.active_accounts.order(:id).first)
      true
    end

    if left
      redirect_to dashboard_path, notice: "Je hebt het account '#{@account.name}' verlaten"
    else
      redirect_to settings_path, alert: "Je kunt niet vertrekken als enige admin. Maak eerst iemand anders admin of verwijder het account."
    end
  end

  private

  # Missing funds and funds you are not an active member of get the same answer.
  def set_account
    @membership = current_user.active_memberships.includes(:account).find_by(account_id: params[:id])
    @account = @membership&.account

    redirect_to dashboard_path, alert: "Account niet gevonden." unless @account
  end

  def require_account_admin
    redirect_to settings_path, alert: "Alleen admins kunnen dit doen." unless @membership.admin?
  end

  def account_params
    params.require(:account).permit(:name, :description)
  end
end
