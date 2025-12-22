require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
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
    get settings_path
    assert_response :success
    assert_select "h2", text: "Instellingen"
  end

  test "should update account settings" do
    patch settings_path, params: {
      account: {
        name: "Updated Name",
        description: "Updated description",
        split_method: "proportional"
      }
    }

    assert_response :redirect
    follow_redirect!
    assert_response :success

    @account.reload
    assert_equal "Updated Name", @account.name
    assert_equal "Updated description", @account.description
    assert_equal "proportional", @account.split_method
  end

  test "should not update with invalid data" do
    patch settings_path, params: {
      account: {
        name: "", # Empty name should fail validation
        description: "Test"
      }
    }

    assert_response :unprocessable_entity
  end
end
