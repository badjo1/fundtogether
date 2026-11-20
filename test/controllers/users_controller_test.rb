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
        active: true,
        joined_at: 2.weeks.ago
      )
    end

    get users_path
    assert_response :success

    # Check total members count is displayed, each member counted once
    assert_select ".text-3xl.font-bold.text-gray-900", text: "2"
  end

  test "should display user role badges" do
    get users_path
    assert_response :success

    # Admin badge should be purple
    assert_select ".bg-purple-100.text-purple-800", text: "Admin"
  end

  test "should mark current user with (Jij)" do
    get users_path
    assert_response :success

    # Check current user is marked
    assert_select "span.text-gray-500", text: "(Jij)"
  end

  test "should not open the page once the user has no membership left" do
    @account.account_memberships.destroy_all

    get users_path
    assert_redirected_to new_account_path
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

  test "should redirect to new account if the user has no fund" do
    sign_in_as create_user("zonderfonds")

    get users_path
    assert_redirected_to new_account_path
    assert_equal "Maak eerst een account aan om te beginnen", flash[:alert]
  end

  test "should use a fund the user is active in when none is selected" do
    @user.update(current_account: nil)

    get users_path
    assert_response :success
  end
end
