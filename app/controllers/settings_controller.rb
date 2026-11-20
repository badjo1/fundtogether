class SettingsController < ApplicationController
  before_action :require_current_account
  before_action :require_explicit_fund_admin, only: :update
  before_action :set_account

  def index
    # View renders the form with @account
  end

  def update
    if @account.update(account_params)
      current_user.update!(current_account: @account)
      redirect_to settings_path, notice: "Instellingen succesvol bijgewerkt"
    else
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = @fund || current_account
  end

  def account_params
    params.require(:account).permit(:name, :description)
  end
end
