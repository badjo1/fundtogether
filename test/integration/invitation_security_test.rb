require "test_helper"

class InvitationSecurityTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  setup do
    @fund = accounts(:two)
    @admin = add_to_fund(users(:one), @fund, role: "admin")
    @bearer = Invitation.create!(account: @fund, invited_by: @admin)
    @addressed = Invitation.create!(account: @fund, invited_by: @admin,
                                    email: "invitee@example.com", email_verified_at: Time.current)
  end

  def verification_link_from_last_mail
    perform_enqueued_jobs
    ActionMailer::Base.deliveries.last.text_part.decoded[%r{/invitations/\S+/verify/\S+}]
  end

  def verify_bearer_link(address)
    post request_email_verification_invitation_path(@bearer.token), params: { email: address }
    assert_redirected_to accept_invitation_path(@bearer.token)
    get verification_link_from_last_mail
    assert_redirected_to accept_invitation_path(@bearer.token)
    assert @bearer.reload.email_verified?
  end

  def member?(user, account = @fund)
    account.account_memberships.exists?(user: user)
  end

  # The link/QR/WhatsApp flow, start to finish, through the real mail
  test "bearer link: new user verifies address, registers and lands in the fund as member" do
    get open_invitation_path(@bearer.token)
    assert_redirected_to accept_invitation_path(@bearer.token)
    follow_redirect!
    assert_response :success
    assert_select "form[action='#{request_email_verification_invitation_path(@bearer.token)}']"
    assert_select "form[action='#{reject_invitation_path(@bearer.token)}']"

    verify_bearer_link("nieuw@example.com")
    follow_redirect!
    assert_response :success
    assert_select "form[action='#{process_invitation_path(@bearer.token)}']"

    post process_invitation_path(@bearer.token)
    assert_redirected_to register_path
    follow_redirect!
    assert_select "input[name='user[email_address]'][value='nieuw@example.com']"

    assert_difference("User.count", 1) do
      post register_path, params: { user: { name: "Nieuw", email_address: "nieuw@example.com",
                                            password: "password123", password_confirmation: "password123" } }
    end
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success

    user = User.find_by!(email_address: "nieuw@example.com")
    assert_equal "member", @fund.account_memberships.find_by!(user: user).role
    assert_equal @fund, user.current_account
    assert @bearer.reload.accepted?
    assert_nil session[:pending_invitation_token]
    assert_nil session[:invitation_email]
  end

  test "bearer link: existing user verifies own address and logs in" do
    user = create_user("bestaand")
    verify_bearer_link(user.email_address)

    post process_invitation_path(@bearer.token)
    assert_redirected_to login_path

    log_in_with_password(user)
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_equal "member", @fund.account_memberships.find_by!(user: user).role
    assert_equal @fund, user.reload.current_account
  end

  test "the accept page explains that a link is a bearer link without on-chain power" do
    get accept_invitation_path(@bearer.token)
    assert_select "body", text: /Iedereen met deze link/
    assert_select "body", text: /on-chain/
  end

  # Bypass 1: overwriting the address
  test "a verified address cannot be overwritten" do
    assert_no_enqueued_emails do
      post request_email_verification_invitation_path(@addressed.token), params: { email: "attacker@evil.test" }
    end
    assert_equal "invitee@example.com", @addressed.reload.email
    assert @addressed.email_verified?
  end

  test "an address verified through a bearer link cannot be overwritten" do
    verify_bearer_link("first@example.com")

    post request_email_verification_invitation_path(@bearer.token), params: { email: "attacker@evil.test" }

    assert_equal "first@example.com", @bearer.reload.email
  end

  test "no mail and no change on expired or accepted invitations" do
    expired = invitations(:expired_status)
    accepted = invitations(:accepted)

    assert_no_enqueued_emails do
      post request_email_verification_invitation_path(expired.token), params: { email: "attacker@evil.test" }
      assert_response :gone
      post request_email_verification_invitation_path(accepted.token), params: { email: "attacker@evil.test" }
      assert_redirected_to root_path
    end
    assert_equal "expiredstatus@example.com", expired.reload.email
    assert_equal "accepted@example.com", accepted.reload.email
  end

  test "a blank or invalid address is refused and sends nothing" do
    [ "", "   ", "geen-email" ].each do |address|
      assert_no_enqueued_emails do
        post request_email_verification_invitation_path(@bearer.token), params: { email: address }
      end
      assert_redirected_to accept_invitation_path(@bearer.token)
      assert_nil @bearer.reload.email
    end
  end

  # Bypass 2: the helper endpoint
  test "send_email is admin only and does not verify for anyone else" do
    other_admin = add_to_fund(create_user("otheradmin"), accounts(:one), role: "admin")
    member = add_to_fund(create_user("lid"), @fund)
    viewer = add_to_fund(create_user("kijker"), @fund, role: "viewer")
    inactive_admin = add_to_fund(create_user("oud"), @fund, role: "admin", active: false)

    [ create_user("buiten"), other_admin, member, viewer, inactive_admin ].each do |user|
      sign_in_as user
      assert_no_enqueued_emails do
        post send_email_invitation_path(@bearer.token), params: { email: "attacker@evil.test" }
      end
      assert_nil @bearer.reload.email, "#{user.name} addressed the invitation"
      assert_not @bearer.email_verified?, "#{user.name} verified the invitation"

      existing = [ response.location, flash[:alert] ]
      post send_email_invitation_path("bestaat-niet"), params: { email: "attacker@evil.test" }
      assert_equal [ response.location, flash[:alert] ], existing
    end
  end

  test "send_email needs a login" do
    post send_email_invitation_path(@bearer.token), params: { email: "attacker@evil.test" }
    assert_redirected_to new_session_path
    assert_nil @bearer.reload.email
  end

  test "send_email is refused on expired and accepted invitations and survives a bad address" do
    sign_in_as @admin

    post send_email_invitation_path(invitations(:expired_status).token), params: { email: "x@example.com" }
    assert_response :gone
    post send_email_invitation_path(invitations(:accepted).token), params: { email: "x@example.com" }
    assert_redirected_to root_path

    post send_email_invitation_path(@bearer.token), params: { email: "geen-email" }
    assert_response :redirect
    assert_nil @bearer.reload.email
  end

  # Bypass 3: the token was not bound to the address
  test "a verification token mailed to one address cannot verify another" do
    post request_email_verification_invitation_path(@bearer.token), params: { email: "attacker@evil.test" }
    attacker_link = verification_link_from_last_mail

    post request_email_verification_invitation_path(@bearer.token), params: { email: "victim@example.com" }
    assert_equal "victim@example.com", @bearer.reload.email

    get attacker_link

    assert_not @bearer.reload.email_verified?, "attacker's token verified the victim's address"
    assert_redirected_to open_invitation_path(@bearer.token)
  end

  test "a token signed for an address fails once the stored address differs" do
    @bearer.update!(email: "attacker@evil.test")
    @bearer.generate_email_verification_token
    @bearer.save!
    token = @bearer.email_verification_token

    @bearer.update_columns(email: "victim@example.com")

    assert_nil Invitation.find_by_email_verification_token(token)
  end

  test "changing an unverified address replaces the token" do
    post request_email_verification_invitation_path(@bearer.token), params: { email: "first@example.com" }
    first_token = @bearer.reload.email_verification_token
    post request_email_verification_invitation_path(@bearer.token), params: { email: "second@example.com" }

    assert_not_equal first_token, @bearer.reload.email_verification_token
    assert_nil Invitation.find_by_email_verification_token(first_token)
  end

  # Addressed invitations: the accepting user must be the addressee
  test "logging in as someone else does not consume an addressed invitation" do
    post process_invitation_path(@addressed.token)
    other = create_user("ander")

    log_in_with_password(other)

    assert_redirected_to dashboard_path
    assert flash[:alert].present?
    assert_not member?(other)
    assert @addressed.reload.pending?
    assert_nil session[:pending_invitation_token]
  end

  test "registering with a different address does not consume an addressed invitation" do
    post process_invitation_path(@addressed.token)
    assert_redirected_to register_path

    post register_path, params: { user: { name: "Aanvaller", email_address: "attacker@evil.test",
                                          password: "password123", password_confirmation: "password123" } }

    attacker = User.find_by!(email_address: "attacker@evil.test")
    assert_not member?(attacker)
    assert @addressed.reload.pending?
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_redirected_to new_account_path
    follow_redirect!
    assert_select "body", text: /uitnodiging/i
  end

  test "address matching ignores case" do
    user = create_user("hoofdletter", email: "invitee@example.com")
    @addressed.update_columns(email: "Invitee@Example.com")
    sign_in_as user

    post process_invitation_path(@addressed.token)

    assert member?(user)
  end

  # Logged-in users accept directly
  test "a logged-in addressee accepts directly and lands on a working page" do
    user = create_user("direct", email: "invitee@example.com")
    sign_in_as user

    get accept_invitation_path(@addressed.token)
    assert_response :success
    assert_select "form[action='#{process_invitation_path(@addressed.token)}']"

    post process_invitation_path(@addressed.token)

    assert_redirected_to dashboard_path
    assert_equal "Je bent toegevoegd aan #{@fund.name}!", flash[:notice]
    follow_redirect!
    assert_response :success
    assert_equal @fund, user.reload.current_account
    assert @addressed.reload.accepted?
  end

  test "a logged-in user with another address is refused and told why" do
    user = create_user("verkeerd")
    sign_in_as user

    get accept_invitation_path(@addressed.token)
    assert_response :success
    assert_select "form[action='#{process_invitation_path(@addressed.token)}']", count: 0

    post process_invitation_path(@addressed.token)

    assert_redirected_to accept_invitation_path(@addressed.token)
    assert flash[:alert].present?
    assert_not member?(user)
    assert @addressed.reload.pending?
  end

  test "an unverified invitation cannot be accepted, logged in or not" do
    user = create_user("ongeverifieerd")
    @bearer.update!(email: user.email_address)

    post process_invitation_path(@bearer.token)
    assert_redirected_to accept_invitation_path(@bearer.token)
    assert_nil session[:pending_invitation_token]

    sign_in_as user
    post process_invitation_path(@bearer.token)
    assert_redirected_to accept_invitation_path(@bearer.token)
    assert_not member?(user)
  end

  # Already a member
  test "a member accepting directly is told so and nothing breaks" do
    user = add_to_fund(create_user("lid", email: "invitee@example.com"), @fund)
    sign_in_as user

    assert_no_difference("AccountMembership.count") do
      post process_invitation_path(@addressed.token)
    end

    assert_redirected_to dashboard_path
    assert_match(/al lid/, flash[:notice])
    assert @addressed.reload.accepted?
  end

  test "a member with a pending invitation can still log in" do
    user = add_to_fund(create_user("lid", email: "invitee@example.com"), @fund)
    post process_invitation_path(@addressed.token)

    log_in_with_password(user)

    assert_redirected_to dashboard_path
    assert cookies["session_id"].present?
    assert_nil session[:pending_invitation_token]
  end

  test "a former member is reactivated as member, not with their old role" do
    user = add_to_fund(create_user("oud", email: "invitee@example.com"), @fund, role: "admin", active: false)
    sign_in_as user

    assert_no_difference("AccountMembership.count") do
      post process_invitation_path(@addressed.token)
    end

    membership = @fund.account_memberships.find_by!(user: user)
    assert membership.active?
    assert_equal "member", membership.role
  end

  # A stale token on a shared browser
  test "logging out clears a pending invitation" do
    user = create_user("eerste", email: "invitee@example.com")
    next_person = create_user("tweede")
    post process_invitation_path(@addressed.token)
    assert_equal @addressed.token, session[:pending_invitation_token]

    log_in_with_password(next_person)
    delete session_path
    assert_nil session[:pending_invitation_token]

    log_in_with_password(user)
    assert_not member?(user), "token should not survive logout"
  end

  test "logout empties the session even with a token set while logged out and a failed login" do
    post process_invitation_path(@addressed.token)
    log_in_with_password(users(:two), password: "fout-wachtwoord")
    assert_equal @addressed.token, session[:pending_invitation_token]

    log_in_with_password(users(:two))

    assert_not member?(users(:two))
    assert_nil session[:pending_invitation_token]
    assert_nil session[:invitation_email]
  end

  test "login replaces the session id" do
    post process_invitation_path(@addressed.token)
    before = session.id.to_s
    assert before.present?

    log_in_with_password(users(:two))

    assert_not_equal before, session.id.to_s
  end

  test "registering replaces the session id" do
    post process_invitation_path(@addressed.token)
    before = session.id.to_s

    post register_path, params: { user: { name: "Nieuw", email_address: "invitee@example.com",
                                          password: "password123", password_confirmation: "password123" } }

    assert_not_equal before, session.id.to_s
  end

  test "login keeps the page the user was sent away from" do
    sign_out
    get users_path
    assert_redirected_to new_session_path

    log_in_with_password(@admin)

    assert_redirected_to users_url
  end

  # Rejecting
  test "accepted, expired and rejected invitations cannot be rejected" do
    sign_in_as users(:two)

    post reject_invitation_path(invitations(:accepted).token)
    assert_redirected_to root_path
    assert invitations(:accepted).reload.accepted?

    post reject_invitation_path(invitations(:expired_status).token)
    assert_response :gone
    assert invitations(:expired_status).reload.pending?
  end

  test "a verified invitation cannot be rejected anonymously or by an unrelated user" do
    post reject_invitation_path(@addressed.token)
    assert_redirected_to accept_invitation_path(@addressed.token)
    assert @addressed.reload.pending?

    sign_in_as create_user("buiten")
    post reject_invitation_path(@addressed.token)
    assert_redirected_to accept_invitation_path(@addressed.token)
    assert @addressed.reload.pending?
  end

  test "the addressee and a fund admin can reject a verified invitation" do
    sign_in_as create_user("genodigde", email: "invitee@example.com")
    post reject_invitation_path(@addressed.token)
    assert_redirected_to root_path
    assert @addressed.reload.rejected?

    second = Invitation.create!(account: @fund, invited_by: @admin, email: "b@example.com",
                                email_verified_at: Time.current)
    sign_in_as @admin
    post reject_invitation_path(second.token)
    assert second.reload.rejected?
  end

  test "whoever holds an unclaimed bearer link can decline it, without a login" do
    post reject_invitation_path(@bearer.token)

    assert_redirected_to root_path
    assert @bearer.reload.rejected?
  end

  test "the accept page does not offer an anonymous reject of a verified invitation" do
    get accept_invitation_path(@addressed.token)

    assert_response :success
    assert_select "form[action='#{reject_invitation_path(@addressed.token)}']", count: 0
  end

  # Rate limits
  test "verification mail is limited per link" do
    with_counting_rate_limit_store do
      3.times do |i|
        post request_email_verification_invitation_path(@bearer.token), params: { email: "a#{i}@example.com" }
        assert_redirected_to accept_invitation_path(@bearer.token)
      end

      assert_no_enqueued_emails do
        post request_email_verification_invitation_path(@bearer.token), params: { email: "a4@example.com" }
      end
      assert_redirected_to root_path
      assert_equal "a2@example.com", @bearer.reload.email
    end
  end

  test "verification mail is limited per address, across links" do
    with_counting_rate_limit_store do
      5.times do
        invitation = Invitation.create!(account: @fund, invited_by: @admin)
        post request_email_verification_invitation_path(invitation.token), params: { email: "a@example.com" }
        assert_redirected_to accept_invitation_path(invitation.token)
      end

      post request_email_verification_invitation_path(@bearer.token), params: { email: "a@example.com" }
      assert_redirected_to root_path
      assert_nil @bearer.reload.email
    end
  end

  test "token endpoints are limited" do
    with_counting_rate_limit_store do
      30.times do
        get accept_invitation_path("geraden")
        assert_equal "Uitnodiging niet gevonden.", flash[:alert]
      end

      get accept_invitation_path("geraden")
      assert_redirected_to root_path
      assert_match(/Te veel/, flash[:alert])
    end
  end

  test "registration is limited" do
    with_counting_rate_limit_store do
      10.times { post register_path, params: { user: { name: "" } } }
      assert_response :unprocessable_entity

      post register_path, params: { user: { name: "" } }
      assert_redirected_to register_path
      assert_match(/Te veel/, flash[:alert])
    end
  end
end
