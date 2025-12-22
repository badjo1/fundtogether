class SettingsController < ApplicationController
  before_action :set_account

  def index
    # View renders the form with @account
  end

  def update
    if @account.update(account_params)
      redirect_to settings_path, notice: "Instellingen succesvol bijgewerkt"
    else
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = current_account

    redirect_to(new_account_path, alert: "Maak eerst een account aan") unless @account
  end

  def account_params
    # Only allow persisted fields
    params.require(:account).permit(:name, :description, :split_method)
  end
end
