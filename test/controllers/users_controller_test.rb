require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = accounts(:one)
    @user.update(current_account: @account)

    # Ensure user is a member of the account
    unless @account.account_memberships.exists?(user: @user)
      @account.account_memberships.create!(
        user: @user,
        role: "admin",
        balance_cents: 15000, # €150.00
        active: true,
        joined_at: 1.month.ago
      )
    end

    sign_in_as @user
  end

  test "should get index" do
    get users_path
    assert_response :success
    assert_select "h2", text: "Groepsleden"
  end

  test "should display correct member stats" do
    # Add another user to test stats
    other_user = users(:two)
    unless @account.account_memberships.exists?(user: other_user)
      @account.account_memberships.create!(
        user: other_user,
        role: "member",
        balance_cents: 25000, # €250.00
        active: true,
        joined_at: 2.weeks.ago
      )
    end

    get users_path
    assert_response :success

    # Check total members count is displayed (at least 1)
    assert_select ".text-3xl.font-bold.text-gray-900"

    # Check average balance is displayed with euro symbol
    assert_select ".text-3xl.font-bold.text-gray-900", text: /€/
  end

  test "should display user balances correctly" do
    # Update balance to known value
    membership = @account.account_memberships.find_by(user: @user)
    membership.update(balance_cents: 12345) # €123.45

    get users_path
    assert_response :success

    # Check balance is displayed
    assert_select ".text-lg.font-bold", text: /€123\.45/
  end

  test "should show negative balances in red" do
    # Set negative balance
    membership = @account.account_memberships.find_by(user: @user)
    membership.update(balance_cents: -5000) # -€50.00

    get users_path
    assert_response :success

    # Check negative balance has red styling
    assert_select ".text-red-600", text: /€-50\.00/
  end

  test "should display user role badges" do
    get users_path
    assert_response :success

    # Admin badge should be purple
    assert_select ".bg-purple-100.text-purple-800", text: "Admin"
  end

  test "should show transaction count per user" do
    # Create some transactions
    3.times do
      @account.transactions.create!(
        from_user: @user,
        transaction_type: "deposit",
        amount_cents: 10000,
        description: "Test deposit",
        token: "EURe",
        status: "confirmed"
      )
    end

    get users_path
    assert_response :success

    # Check transaction count is displayed
    assert_select ".text-lg.font-bold.text-gray-900", text: "3"
  end

  test "should mark current user with (Jij)" do
    get users_path
    assert_response :success

    # Check current user is marked
    assert_select "span.text-gray-500", text: "(Jij)"
  end

  test "should show empty state when no members" do
    # Remove all memberships
    @account.account_memberships.destroy_all

    get users_path
    assert_response :success

    assert_select "p.text-gray-500", text: "Nog geen leden in dit account"
  end

  test "should display pending invitations count" do
    # Clear existing invitations and create new ones
    @account.invitations.destroy_all

    2.times do |i|
      @account.invitations.create!(
        email: "test#{i}@example.com",
        invited_by: @user,
        status: "pending",
        token: SecureRandom.hex(20)
      )
    end

    get users_path
    assert_response :success

    assert_select "span.bg-yellow-100.text-yellow-800", text: /2 In behandeling/
  end

  test "should redirect to new account if no current account" do
    @user.update(current_account: nil)

    get users_path
    assert_redirected_to new_account_path
    assert_equal "Maak eerst een account aan om te beginnen", flash[:alert]
  end
end
