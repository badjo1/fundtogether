require "test_helper"

# H2: the address on an account is unproven until a mailed token comes back with the account's password
# or session. Until then the account can log in, and nothing that needs an identity works.
class EmailConfirmationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.code = "0x"
    @admin = create_user("adminz")
    @fund = Account.create!(name: "Fonds Een")
    add_to_fund(@admin, @fund, role: "admin")
    ActionMailer::Base.deliveries.clear
  end

  teardown { uninstall_fake_rpc }

  def register(email: "bas@example.com", password: "password")
    post register_path, params: { user: { name: "Bas Jansen", email_address: email, password: password, password_confirmation: password } }
  end

  def confirmation_link(mail = ActionMailer::Base.deliveries.last)
    mail.text_part.body.to_s[%r{https?://\S+/email_bevestigen/\S+}]
  end

  def confirmation_path_from(link)
    URI(link).path
  end

  def addressed_invite(email: "bas@example.com")
    @fund.invitations.create!(invited_by: @admin, email: email, email_verified_at: Time.current)
  end

  test "registering sends a confirmation mail and leaves the account unconfirmed" do
    perform_enqueued_jobs { register }
    user = User.find_by!(email_address: "bas@example.com")
    assert_not user.email_confirmed?
    assert_equal [ "bas@example.com" ], ActionMailer::Base.deliveries.last.to
    assert_match "fundtogether.test", confirmation_link
    assert_not_nil user.email_confirmation_sent_at
  end

  test "an unconfirmed account can log in and sees how to confirm" do
    user = create_user("bas", confirmed: false)
    log_in_with_password(user)
    assert_redirected_to root_url
    get wallet_page_path
    assert_response :success
    assert_select "[data-testid=email-unconfirmed]"
  end

  test "a GET on the link confirms nothing, because mail scanners follow links" do
    user = create_user("bas", confirmed: false)
    get email_confirmation_path(user.generate_token_for(:email_confirmation))
    assert_response :success
    assert_not user.reload.email_confirmed?
  end

  test "the owner of the session confirms with one click and the token is single use" do
    user = create_user("bas", confirmed: false)
    token = user.generate_token_for(:email_confirmation)
    sign_in_as user
    post email_confirmation_path(token)
    assert user.reload.email_confirmed?
    confirmed_at = user.email_confirmed_at
    post email_confirmation_path(token)
    assert_equal confirmed_at, user.reload.email_confirmed_at
    get email_confirmation_path(token)
    assert_response :gone
  end

  test "someone who only has the mail cannot confirm: pre-registering a victim's address gets nowhere" do
    attacker_account = create_user("victim", confirmed: false)
    token = attacker_account.generate_token_for(:email_confirmation)
    post email_confirmation_path(token), params: { password: "not-the-password" }
    assert_not attacker_account.reload.email_confirmed?
    assert_response :unprocessable_entity
  end

  test "without a session the account's password confirms" do
    user = create_user("bas", confirmed: false)
    post email_confirmation_path(user.generate_token_for(:email_confirmation)), params: { password: "password" }
    assert user.reload.email_confirmed?
    assert_redirected_to dashboard_path
  end

  test "a confirmation token expires after 24 hours" do
    user = create_user("bas", confirmed: false)
    token = user.generate_token_for(:email_confirmation)
    travel 25.hours do
      get email_confirmation_path(token)
      assert_response :gone
      post email_confirmation_path(token), params: { password: "password" }
      assert_not user.reload.email_confirmed?
    end
  end

  test "resending is limited per account" do
    user = create_user("bas", confirmed: false)
    sign_in_as user
    with_counting_rate_limit_store do
      perform_enqueued_jobs do
        5.times { post resend_email_confirmation_path }
      end
    end
    assert_equal 3, ActionMailer::Base.deliveries.size
  end

  test "resending says so in Dutch and does nothing once confirmed" do
    user = create_user("bas")
    sign_in_as user
    assert_no_enqueued_emails { post resend_email_confirmation_path }
    assert_redirected_to dashboard_path
    assert_match "al bevestigd", flash[:notice]
  end

  test "a forwarded addressed invite no longer joins: register as that address, stay out until confirmed" do
    invitation = addressed_invite
    post process_invitation_path(invitation.token)
    assert_redirected_to register_path

    perform_enqueued_jobs { register }
    assert_redirected_to email_confirmation_pending_path
    user = User.find_by!(email_address: "bas@example.com")
    assert_not @fund.active_users.exists?(user.id)
    assert invitation.reload.pending?

    # Direct model call too: no route may get around this.
    assert_not invitation.accept!(user)
  end

  test "after confirming in the same browser the pending invitation completes" do
    invitation = addressed_invite
    post process_invitation_path(invitation.token)
    perform_enqueued_jobs { register }
    post confirmation_path_from(confirmation_link)
    assert_redirected_to dashboard_path
    assert @fund.active_users.exists?(User.find_by!(email_address: "bas@example.com").id)
    assert invitation.reload.accepted?
  end

  test "after confirming in another browser the person lands on the invitation, without joining by itself" do
    invitation = addressed_invite
    user = create_user("bas", email: "bas@example.com", confirmed: false)
    post email_confirmation_path(user.generate_token_for(:email_confirmation)), params: { password: "password" }
    assert_redirected_to accept_invitation_path(invitation.token)
    assert_not @fund.active_users.exists?(user.id)
  end

  test "an admin-addressed invitation is no proof of the address" do
    invitation = addressed_invite
    assert invitation.email_verified?
    post process_invitation_path(invitation.token)
    perform_enqueued_jobs { register }
    assert_not User.find_by!(email_address: "bas@example.com").email_confirmed?
  end

  test "a link invitation's mailed proof confirms the account when it comes back to the same browser" do
    invitation = @fund.invitations.create!(invited_by: @admin)
    perform_enqueued_jobs do
      post request_email_verification_invitation_path(invitation.token), params: { email: "bas@example.com" }
    end
    get verify_invitation_email_path(invitation.token, invitation.reload.email_verification_token)
    post process_invitation_path(invitation.token)
    register
    user = User.find_by!(email_address: "bas@example.com")
    assert user.email_confirmed?
    assert @fund.active_users.exists?(user.id)
  end

  test "a link invitation's mailed proof clicked in another browser confirms nothing" do
    invitation = @fund.invitations.create!(invited_by: @admin)
    perform_enqueued_jobs do
      post request_email_verification_invitation_path(invitation.token), params: { email: "bas@example.com" }
    end
    # The victim clicks it, from their own mail, in their own browser.
    open_session { |other| other.get verify_invitation_email_path(invitation.token, invitation.reload.email_verification_token) }
    assert invitation.reload.email_verified?

    post process_invitation_path(invitation.token)
    register
    user = User.find_by!(email_address: "bas@example.com")
    assert_not user.email_confirmed?
    assert_not @fund.active_users.exists?(user.id)
  end

  test "an unconfirmed account cannot link a wallet: challenge, link and handoff are refused" do
    user = create_user("bas", confirmed: false)
    sign_in_as user
    post wallet_challenges_path, params: { address: address_of(:bob), purpose: "link" }, as: :json
    assert_response :forbidden
    assert_equal "email_not_confirmed", json["error"]

    challenge = WalletChallenge.issue_link!(user: user, session: @signed_in_session, address: address_of(:bob), chain_id: SEPOLIA)
    post wallets_path, params: { address: address_of(:bob), nonce: challenge.nonce, signature: sign_personal(:bob, challenge.message) }, as: :json
    assert_response :forbidden
    assert_equal 0, user.wallets.count

    post wallet_handoffs_path, as: :json
    assert_response :forbidden
    post wallet_page_handoff_path, as: :turbo_stream
    assert_redirected_to wallet_page_path
  end

  test "an unconfirmed member is not offered as a signer and a proposal naming their wallet is refused" do
    bas = create_user("bas", confirmed: false)
    add_to_fund(bas, @fund)
    link_wallet(@admin, :alice)
    link_wallet(bas, :bob) # An older row: linking itself is refused now.
    @admin.update!(current_account: @fund)
    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    @fake.owners = [ address_of(:alice) ]
    @fake.code = "0x60"

    sign_in_as @admin
    get new_account_proposal_page_path(@fund, kind: "add_owner")
    assert_response :success
    assert_no_match address_of(:bob), response.body.downcase

    post account_proposals_path(@fund), params: { kind: "add_owner", title: "Bas erbij", params: { owner: address_of(:bob), threshold: "1" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "owner_email_unconfirmed", json["error"]
  end

  test "an unconfirmed admin cannot send invitations from our domain" do
    bas = create_user("bas", confirmed: false)
    fund = Account.create!(name: "Eigen fonds")
    add_to_fund(bas, fund, role: "admin")
    sign_in_as bas
    assert_no_enqueued_emails do
      post invitations_path, params: { account_id: fund.id, invitation: { email: "slachtoffer@example.com" } }
    end
    assert_equal 0, fund.invitations.count
  end

  test "a password reset proves the mailbox and hands a squatted account to the address's owner" do
    squatted = create_user("victim", email: "victim@example.com", confirmed: false)
    squatter_session = squatted.sessions.create!
    token = squatted.password_reset_token
    patch password_path(token), params: { password: "nieuw-wachtwoord", password_confirmation: "nieuw-wachtwoord" }
    assert squatted.reload.email_confirmed?
    assert_not Session.exists?(squatter_session.id)
  end

  test "abandoned unconfirmed accounts with nothing attached are removed, others stay" do
    abandoned = create_user("oud", confirmed: false)
    abandoned.update_column(:created_at, 8.days.ago)
    recent = create_user("nieuw", confirmed: false)
    with_fund = create_user("metfonds", confirmed: false)
    with_fund.update_column(:created_at, 8.days.ago)
    add_to_fund(with_fund, @fund)
    UnconfirmedUserCleanupJob.perform_now
    assert_not User.exists?(abandoned.id)
    assert User.exists?(recent.id)
    assert User.exists?(with_fund.id)
    assert User.exists?(@admin.id)
  end
end
