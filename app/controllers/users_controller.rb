class UsersController < ApplicationController
  def index
    @users = current_account&.active_users || []
  end
end
