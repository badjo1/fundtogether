require "test_helper"

class RegistrationFlowTest < ActionDispatch::IntegrationTest
  def register(email: "nieuw@example.com", password: "password123")
    post register_path, params: { user: { name: "Nieuw", email_address: email,
                                          password: password, password_confirmation: password } }
  end

  test "registering logs the user in with the same cookie login uses" do
    register

    assert_redirected_to dashboard_path
    assert cookies["session_id"].present?
    assert_nil cookies["session_token"].presence

    follow_redirect!
    assert_redirected_to new_account_path, "a logged-in user without funds goes to fund creation, not to login"
    follow_redirect!
    assert_response :success
    assert logged_in?
  end

  test "registered users stay logged in across requests with a fresh Current" do
    register
    Current.reset

    get new_account_path

    assert_response :success
  end

  test "a password under 8 characters is refused, as the form promises" do
    assert_no_difference("User.count") do
      register(password: "kort")
    end
    assert_response :unprocessable_entity
  end

  test "password reset also enforces the minimum length" do
    user = users(:one)

    patch password_path(user.password_reset_token), params: { password: "kort", password_confirmation: "kort" }

    assert user.reload.authenticate("password")
  end

  test "login with the right password logs in" do
    log_in_with_password(users(:one))

    assert_response :redirect
    assert cookies["session_id"].present?
    assert logged_in?
  end

  test "login with the wrong password does not log in" do
    log_in_with_password(users(:one), password: "password123")

    assert_redirected_to new_session_path
    assert cookies["session_id"].blank?
    assert_not logged_in?
  end

  test "logging out ends the session" do
    log_in_with_password(users(:one))
    delete session_path

    assert_redirected_to new_session_path
    assert_not logged_in?
  end
end
