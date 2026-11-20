require "test_helper"

# M5, M6, M8, M13, M14, and the handoff decision.
class IdentityAndLoggingTest < ActionDispatch::IntegrationTest
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

  def captured_logs
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    logger.level = :debug
    Rails.logger.broadcast_to(logger)
    begin
      yield
    ensure
      Rails.logger.stop_broadcasting_to(logger)
    end
    io.string
  end

  # --- M5

  test "the link message names the account's email, and the domain" do
    sign_in_as @admin
    post wallet_challenges_path, params: { address: address_of(:bob), purpose: "link" }, as: :json
    assert_response :created
    assert_includes json["message"], "Account: #{@admin.email_address}"
    assert json["message"].start_with?("fundtogether.test wants you")
    assert json["message"].ascii_only?
  end

  test "linking and unlinking a wallet send mail" do
    sign_in_as @admin
    post wallet_challenges_path, params: { address: address_of(:bob), purpose: "link" }, as: :json
    challenge = json
    perform_enqueued_jobs do
      post wallets_path, params: { address: address_of(:bob), nonce: challenge["nonce"], signature: sign_personal(:bob, challenge["message"]) }, as: :json
    end
    assert_response :created
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @admin.email_address ], mail.to
    assert_includes mail.text_part.body.to_s, Chain::Address.checksum(address_of(:bob))
    assert_match "gekoppeld", mail.subject

    wallet = @admin.wallets.active.first
    perform_enqueued_jobs { delete wallet_page_unlink_path(wallet) }
    assert_match "ontkoppeld", ActionMailer::Base.deliveries.last.subject

    other = link_wallet(@admin, :carol)
    perform_enqueued_jobs { delete wallet_path(other), as: :json }
    assert_match "ontkoppeld", ActionMailer::Base.deliveries.last.subject
  end

  test "linking the same address again sends no second mail" do
    wallet = link_wallet(@admin, :bob)
    sign_in_as @admin
    post wallet_challenges_path, params: { address: wallet.address, purpose: "link" }, as: :json
    challenge = json
    assert_no_enqueued_emails do
      post wallets_path, params: { address: wallet.address, nonce: challenge["nonce"], signature: sign_personal(:bob, challenge["message"]) }, as: :json
    end
  end

  test "the handoff confirmation page names the account's email" do
    sign_in_as @admin
    _, token = WalletChallenge.issue_handoff!(user: @admin, session: @signed_in_session)
    get wallet_handoff_path(token), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_includes response.body, @admin.email_address
  end

  # --- M6

  BIDI = "Voor‮eraf‬ ​vakantie\u0000".freeze

  test "bidi, zero-width and control characters are removed from titles and names at input" do
    assert_equal "Vooreraf vakantie", SafeText.clean(BIDI)
    user = User.create!(name: "Bas‮ Jansen", email_address: "b@example.com", password: "password")
    assert_equal "Bas Jansen", user.name
    fund = Account.create!(name: "Fonds⁦ Twee")
    assert_equal "Fonds Twee", fund.name

    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    link_wallet(@admin, :alice)
    @fake.owners = [ address_of(:alice) ]
    @fake.code = "0x60"
    sign_in_as @admin
    post account_proposals_path(@fund), params: { kind: "transfer_token", title: "Naar‮ Bob", params: { recipient: address_of(:dave), amount: "1" } }, as: :json
    assert_response :created
    assert_equal "Naar Bob", json["title"]
  end

  test "a title that is only control characters is refused" do
    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    @fake.owners = [ address_of(:alice) ]
    sign_in_as @admin
    post account_proposals_path(@fund), params: { kind: "transfer_token", title: "‮​", params: { recipient: address_of(:dave), amount: "1" } }, as: :json
    assert_equal "invalid_title", json["error"]
  end

  test "rows already stored are neutralised at display, and titles are labelled and isolated" do
    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    link_wallet(@admin, :alice)
    @fake.owners = [ address_of(:alice) ]
    @fake.code = "0x60"
    sign_in_as @admin
    post account_proposals_path(@fund), params: { kind: "transfer_token", title: "Gewoon", params: { recipient: address_of(:dave), amount: "1" } }, as: :json
    proposal = SafeProposal.find(json["id"])
    proposal.update_column(:title, "Oud‮ rij")
    User.where(id: @admin.id).update_all(name: "Beheer‮ der")

    get account_proposal_page_path(@fund, proposal)
    assert_no_match "‮", response.body
    assert_select "bdi", text: "Oud rij"
    assert_match "tekst van de indiener", response.body
    get list_account_proposal_pages_path(@fund)
    assert_no_match "‮", response.body
    assert_select "bdi", text: "Oud rij"
    get account_proposal_path(@fund, proposal), as: :json
    assert_equal "Oud rij", json["title"]
    assert_equal "Beheer der", json["proposer"]["name"]
  end

  test "members with the same name are flagged, also when only case or spacing differs, and addresses show in full" do
    twin = add_to_fund(create_user("twin"), @fund)
    twin.update!(name: "ADMINZ ")
    link_wallet(twin, :carol)
    assert_equal 1, @fund.duplicate_member_names.size
    sign_in_as @admin
    get users_path(account_id: @fund.id)
    assert_select "[data-testid=duplicate-name]", 2
    assert_includes response.body, Chain::Address.checksum(address_of(:carol))
  end

  test "an add-owner form shows full checksummed addresses, a duplicate warning and the out-of-band advice" do
    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    link_wallet(@admin, :alice)
    twin = add_to_fund(create_user("twin"), @fund)
    twin.update!(name: "Adminz")
    link_wallet(twin, :carol)
    @fake.owners = [ address_of(:alice) ]
    @fake.code = "0x60"
    sign_in_as @admin
    get new_account_proposal_page_path(@fund, kind: "add_owner")
    assert_includes response.body, Chain::Address.checksum(address_of(:carol))
    assert_match "via een ander kanaal", response.body
    assert_select "[data-testid=duplicate-name]"
  end

  test "a list row names recipient and address, not a bare name" do
    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    link_wallet(@admin, :alice)
    @fake.owners = [ address_of(:alice) ]
    @fake.balance = 10
    @fake.code = "0x60"
    sign_in_as @admin
    post account_proposals_path(@fund), params: { kind: "transfer_token", title: "Naar mezelf", params: { recipient: address_of(:alice), amount: "1" } }, as: :json
    get list_account_proposal_pages_path(@fund)
    checksum = Chain::Address.checksum(address_of(:alice))
    assert_includes response.body, "#{checksum[0, 6]}…#{checksum[-4..]}"
  end

  # --- M8

  test "tokens stay out of every log line: paths, redirects and job arguments" do
    invitation = @fund.invitations.create!(invited_by: @admin)
    secrets = [ invitation.token ]
    logs = captured_logs do
      get open_invitation_path(invitation.token)
      get accept_invitation_path(invitation.token)

      reset = @admin.password_reset_token
      secrets << reset
      get edit_password_path(reset)

      sign_in_as @admin
      _, handoff = WalletChallenge.issue_handoff!(user: @admin, session: @signed_in_session)
      secrets << handoff
      get wallet_handoff_path(handoff), headers: { "Accept" => "text/html" }

      perform_enqueued_jobs do
        post invitations_path, params: { account_id: @fund.id, invitation: { email: "bas@example.com" } }
        latest = Invitation.order(:id).last
        secrets << latest.token
        post send_email_invitation_path(invitation.token), params: { email: "cor@example.com" }
      end

      unconfirmed = create_user("bas2", confirmed: false)
      confirm = unconfirmed.generate_token_for(:email_confirmation)
      secrets << confirm
      get email_confirmation_path(confirm)

      verifiable = @fund.invitations.create!(invited_by: @admin)
      perform_enqueued_jobs do
        post request_email_verification_invitation_path(verifiable.token), params: { email: "dirk@example.com" }
      end
      secrets << verifiable.token
      verification = verifiable.reload.email_verification_token
      secrets << verification
      get verify_invitation_email_path(verifiable.token, verification)
    end
    secrets.each { |secret| assert_not_includes logs, secret }
    assert_match "[FILTERED]", logs
    assert_match %r{Started GET "/invitations/\[FILTERED\]/open"}, logs
  end

  test "signature, address and nonce parameters are filtered" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    clean = filter.filter("signature" => "0xabc", "address" => "0xdef", "nonce" => "n1", "deploy_tx_hash" => "0x1")
    assert_equal({ "signature" => "[FILTERED]", "address" => "[FILTERED]", "nonce" => "[FILTERED]", "deploy_tx_hash" => "0x1" }, clean)
  end

  # --- M13

  test "a session stops working after the idle limit and the absolute limit" do
    sign_in_as @admin
    get wallet_page_path
    assert_response :success
    travel Session::IDLE_LIMIT + 1.minute do
      get wallet_page_path
      assert_redirected_to new_session_path
      assert_not Session.exists?(@signed_in_session.id)
    end

    sign_in_as @admin
    start = Time.current
    4.times do |i|
      travel_to start + ((i + 1) * (Session::IDLE_LIMIT - 1.hour)) do
        get wallet_page_path
        assert_response :success, "regular use keeps it alive up to the absolute limit"
      end
    end
    travel Session::ABSOLUTE_LIMIT + 1.minute do
      get wallet_page_path
      assert_redirected_to new_session_path
    end
  end

  test "activity keeps a session alive, written at most every few minutes" do
    sign_in_as @admin
    get wallet_page_path
    first = @signed_in_session.reload.last_seen_at
    assert_not_nil first
    get wallet_page_path
    assert_equal first, @signed_in_session.reload.last_seen_at
    travel 10.minutes do
      get wallet_page_path
      assert_operator @signed_in_session.reload.last_seen_at, :>, first
    end
  end

  test "the login cookie expires with the session instead of in twenty years" do
    log_in_with_password(@admin)
    cookie = response.headers["Set-Cookie"].then { |value| Array(value).join("\n") }[/session_id=[^\n]*/]
    expires = Time.zone.parse(cookie[/expires=([^;]+)/i, 1])
    assert_operator expires, :<=, Session::ABSOLUTE_LIMIT.from_now + 1.minute
  end

  test "a person sees their sessions and can end one or all others, not someone else's" do
    sign_in_as @admin
    other = @admin.sessions.create!(user_agent: "Telefoon", ip_address: "10.0.0.1")
    third = @admin.sessions.create!(user_agent: "Laptop", ip_address: "10.0.0.2")
    stranger = create_user("vreemde").sessions.create!
    get sessions_list_path
    assert_response :success
    assert_match "Telefoon", response.body
    delete session_revoke_path(other)
    assert_not Session.exists?(other.id)
    delete session_revoke_path(stranger)
    assert Session.exists?(stranger.id)
    delete sessions_revoke_others_path
    assert_not Session.exists?(third.id)
    assert Session.exists?(@signed_in_session.id)
  end

  test "a handoff grant dies with an expired session" do
    sign_in_as @admin
    challenge, = WalletChallenge.issue_handoff!(user: @admin, session: @signed_in_session)
    challenge.consume!
    @signed_in_session.update_column(:created_at, (Session::ABSOLUTE_LIMIT + 1.minute).ago)
    assert_not @signed_in_session.reload.usable?
    assert_not challenge.reload.handoff_grant_active?
  end

  # --- M14

  test "login is limited per address however the source address rotates" do
    with_counting_rate_limit_store do
      25.times do |i|
        post session_path, params: { email_address: @admin.email_address, password: "fout" }, headers: { "REMOTE_ADDR" => "203.0.113.#{i}" }
      end
      post session_path, params: { email_address: @admin.email_address, password: "password" }, headers: { "REMOTE_ADDR" => "198.51.100.7" }
    end
    assert_match "Te veel pogingen", flash[:alert]
    assert_not logged_in?
  end

  test "password reset mail is limited per address" do
    with_counting_rate_limit_store do
      assert_enqueued_emails(3) do
        6.times { |i| post passwords_path, params: { email_address: @admin.email_address }, headers: { "REMOTE_ADDR" => "203.0.113.#{i}" } }
      end
    end
  end

  test "trusted proxies come from configuration, and a forged header does not move the client address" do
    proxies = TrustedProxies.parse("10.0.0.0/8, 127.0.0.1")
    assert proxies.any? { |proxy| proxy.include?("10.1.2.3") }
    assert_not proxies.any? { |proxy| proxy.include?("192.168.1.1") }
    assert_equal [ IPAddr.new("127.0.0.1"), IPAddr.new("::1") ], TrustedProxies.parse(nil)

    remote = ActionDispatch::RemoteIp.new(->(env) { [ 200, {}, [ env["action_dispatch.remote_ip"].to_s ] ] }, true, proxies)
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "10.1.2.3", "HTTP_X_FORWARDED_FOR" => "1.1.1.1, 203.0.113.9")
    assert_equal "203.0.113.9", remote.call(env).last.first
  end

  # --- Handoff decision

  test "a handoff grant no longer opens proposals or signatures, and the page says to log in in the wallet browser" do
    sign_in_as @admin
    _, token = WalletChallenge.issue_handoff!(user: @admin, session: @signed_in_session)
    cookies.delete("session_id") # The phone has no login cookie. Logging out would end the grant.
    post wallet_handoff_path(token), as: :json
    assert_response :created
    assert_equal "wallet_linking", json["scope"]

    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    @fake.owners = [ address_of(:alice) ]
    get account_proposals_path(@fund) + "/1", as: :json
    assert_response :unauthorized
    post account_proposal_signatures_path(@fund, 1), params: { signature: "0x00" }, as: :json
    assert_response :unauthorized
  end

  test "the page after a handoff tells the phone user how to sign" do
    sign_in_as @admin
    _, token = WalletChallenge.issue_handoff!(user: @admin, session: @signed_in_session)
    cookies.delete("session_id") # The phone has no login cookie. Logging out would end the grant.
    post wallet_handoff_path(token)
    follow_redirect!
    assert_match "log je in deze wallet-browser in", response.body
    assert_select "a[href=?]", new_session_path
  end
end
