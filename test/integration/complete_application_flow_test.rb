require "test_helper"

class CompleteApplicationFlowTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @account = accounts(:one)
    @user.update(current_account: @account)

    # Ensure user is a member of the account
    unless @account.account_memberships.exists?(user: @user)
      @account.account_memberships.create!(
        user: @user,
        role: "admin",
        active: true
      )
    end
  end

  test "all public pages load successfully" do
    # Home page
    get root_path
    assert_response :success
    assert_select "h1" # Just check h1 exists

    # Login page
    get login_path
    assert_response :success
    assert_select "form"

    # Register page
    get register_path
    assert_response :success
    assert_select "form"
  end

  test "login form submission works" do
    post login_path, params: {
      email_address: @user.email_address,
      password: "password"
    }

    # Should redirect after successful login, to a page only a logged-in user can open
    assert_response :redirect
    assert cookies["session_id"].present?
    get settings_path
    assert_response :success
  end

  test "registration form creates new user" do
    assert_difference("User.count", 1) do
      post register_path, params: {
        user: {
          name: "Test User",
          email_address: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_redirected_to new_account_path, "the new user is logged in and has no fund yet"
  end

  test "all authenticated pages load successfully" do
    sign_in_as(@user)

    # Dashboard
    get dashboard_path
    assert_response :success
    assert_select "h2", text: "Dashboard"

    # Users/Members index
    get users_path
    assert_response :success

    # Settings
    get settings_path
    assert_response :success
    assert_select "h2", text: "Instellingen"

    # Account new
    get new_account_path
    assert_response :success
    assert_select "h1,h2" # Just check a heading exists
  end

  test "account settings form submission updates account" do
    sign_in_as(@user)

    patch settings_path, params: {
      account_id: @account.id,
      account: {
        name: "Updated Account Name",
        description: "Updated description"
      }
    }

    assert_response :redirect
    follow_redirect!
    assert_response :success

    @account.reload
    assert_equal "Updated Account Name", @account.name
    assert_equal "Updated description", @account.description
  end

  test "account creation form works" do
    sign_in_as(@user)

    assert_difference("Account.count", 1) do
      assert_difference("AccountMembership.count", 1) do
        post accounts_path, params: {
          account: {
            name: "New Test Account",
            description: "Test description"
          }
        }
      end
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success

    # Check user is admin of new account
    new_account = Account.last
    assert_equal "New Test Account", new_account.name
    assert new_account.account_memberships.find_by(user: @user).admin?
  end

  test "invitation form submission creates invitation" do
    sign_in_as(@user)

    assert_difference("Invitation.count", 1) do
      post invitations_path, params: {
        account_id: @account.id,
        invitation: {
          email: "invitee@example.com"
        }
      }
    end

    assert_response :redirect
  end
end
