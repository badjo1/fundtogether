# Step 2 of the new fund wizard, and a way back to it later.
class FundInvitesController < FundPagesController
  before_action :require_admin

  def show
    @members = @account.active_users.order(:id)
    @pending = @account.invitations.where(status: "pending").order(created_at: :desc)
  end
end
