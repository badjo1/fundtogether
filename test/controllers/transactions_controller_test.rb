require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = accounts(:one)
    @user.update(current_account: @account)

    # Ensure user is a member of the account
    unless @account.account_memberships.exists?(user: @user)
      @account.account_memberships.create!(
        user: @user,
        role: 'admin',
        balance_cents: 0,
        active: true
      )
    end

    sign_in_as @user
  end

  test "should get index" do
    get transactions_path
    assert_response :success
  end
end
