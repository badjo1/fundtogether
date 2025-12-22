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
        balance_cents: 0,
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
      password: "password123"
    }

    # Should redirect after successful login
    assert_response :redirect
    follow_redirect!
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

    assert_response :redirect
  end

  test "all authenticated pages load successfully" do
    sign_in_as(@user)

    # Dashboard
    get dashboard_path
    assert_response :success
    assert_select "h2", text: "Dashboard"

    # Transactions index
    get transactions_path
    assert_response :success
    assert_select "h2", text: "Alle Transacties"

    # Transaction new - deposit
    get new_transaction_path(type: "deposit")
    assert_response :success
    assert_select "h2", text: "Nieuwe Storting"

    # Transaction new - expense
    get new_transaction_path(type: "expense")
    assert_response :success
    assert_select "h2", text: "Nieuwe Uitgave"

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

  test "transaction filters work" do
    sign_in_as(@user)

    # Create test transactions
    @account.transactions.create!(
      from_user: @user,
      transaction_type: "deposit",
      amount_cents: 10000,
      description: "Test deposit",
      token: "EURe",
      status: "confirmed"
    )

    @account.transactions.create!(
      from_user: @user,
      transaction_type: "expense",
      amount_cents: 5000,
      description: "Test expense",
      token: "DUMMY",
      status: "confirmed"
    )

    # Filter by type
    get transactions_path(type: "deposit")
    assert_response :success
    assert_select "h2", text: "Alle Transacties"

    # Filter by status
    get transactions_path(status: "confirmed")
    assert_response :success

    # Filter by token
    get transactions_path(token: "EURe")
    assert_response :success
  end

  test "deposit form submission creates transaction and updates balance" do
    sign_in_as(@user)

    initial_balance = @account.user_balance(@user)

    assert_difference("Transaction.count", 1) do
      post transactions_path, params: {
        transaction: {
          amount_euros: "100.50",
          description: "Test deposit",
          transaction_type: "deposit",
          token: "EURe"
        }
      }
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success

    # Check balance was updated
    @account.reload
    expected_balance = initial_balance + 100.50 # 100.50 euros in cents
    assert_equal expected_balance, @account.user_balance(@user)
  end

  test "expense form submission creates transaction and splits among members" do
    sign_in_as(@user)

    # Add another user to the account if not already a member
    other_user = users(:two)
    unless @account.account_memberships.exists?(user: other_user)
      @account.account_memberships.create!(
        user: other_user,
        role: "member",
        balance_cents: 0,
        active: true
      )
    end

    # Set initial balances
    @account.account_memberships.find_by(user: @user).update(balance_cents: 10000)
    @account.account_memberships.find_by(user: other_user).update(balance_cents: 10000)

    assert_difference("Transaction.count", 1) do
      post transactions_path, params: {
        transaction: {
          amount_euros: "60.00",
          description: "Test expense",
          transaction_type: "expense",
          token: "EURe"
        }
      }
    end

    assert_response :redirect

    # Check expense was split equally between 2 members (30 euros each)
    @account.reload
    user_membership = @account.account_memberships.find_by(user: @user)
    other_membership = @account.account_memberships.find_by(user: other_user)

    # Each should have lost 3000 cents (30 euros)
    assert_equal 7000, user_membership.balance_cents
    assert_equal 7000, other_membership.balance_cents
  end

  test "account settings form submission updates account" do
    sign_in_as(@user)

    patch settings_path, params: {
      account: {
        name: "Updated Account Name",
        description: "Updated description",
        split_method: "proportional"
      }
    }

    assert_response :redirect
    follow_redirect!
    assert_response :success

    @account.reload
    assert_equal "Updated Account Name", @account.name
    assert_equal "Updated description", @account.description
    assert_equal "proportional", @account.split_method
  end

  test "account creation form works" do
    sign_in_as(@user)

    assert_difference("Account.count", 1) do
      assert_difference("AccountMembership.count", 1) do
        post accounts_path, params: {
          account: {
            name: "New Test Account",
            description: "Test description",
            split_method: "equal"
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
        invitation: {
          email: "invitee@example.com"
        }
      }
    end

    assert_response :redirect
  end

  test "dashboard shows correct stats with real data" do
    sign_in_as(@user)

    # Set known balance
    @account.account_memberships.find_by(user: @user).update(balance_cents: 15000)

    # Create transactions
    @account.transactions.create!(
      from_user: @user,
      transaction_type: "deposit",
      amount_cents: 10000,
      description: "Deposit",
      token: "EURe",
      status: "confirmed",
      created_at: Time.current
    )

    @account.transactions.create!(
      from_user: @user,
      transaction_type: "expense",
      amount_cents: 5000,
      description: "Expense",
      token: "EURe",
      status: "confirmed",
      created_at: Time.current
    )

    get dashboard_path
    assert_response :success

    # Check stats are displayed
    assert_select ".text-2xl.font-bold.text-gray-900", text: /€/
  end

  test "transaction new form validates amount" do
    sign_in_as(@user)

    # Try to create transaction with invalid amount
    assert_no_difference("Transaction.count") do
      post transactions_path, params: {
        transaction: {
          amount_euros: "-10",
          description: "Test",
          transaction_type: "deposit",
          token: "EURe"
        }
      }
    end

    # Should render the form again with errors
    assert_response :unprocessable_entity
  end

  test "transaction new form validates description" do
    sign_in_as(@user)

    # Try to create transaction without description
    assert_no_difference("Transaction.count") do
      post transactions_path, params: {
        transaction: {
          amount_euros: "10",
          description: "",
          transaction_type: "deposit",
          token: "EURe"
        }
      }
    end

    assert_response :unprocessable_entity
  end
end
