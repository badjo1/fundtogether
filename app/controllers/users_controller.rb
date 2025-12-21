class UsersController < ApplicationController
  def index
    @users = current_account&.active_users || []
    @pending_invitations = current_account&.invitations&.active || []
  end
end
