require "test_helper"

class WalletHandoffTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @fund = accounts(:one)
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.code = "0x"
  end

  teardown { uninstall_fake_rpc }

  # Issues as a logged-in user and returns the token; the same cookie jar then drops the login,
  # like a wallet browser that never had it.
  def issue_token
    sign_in_as @user
    post wallet_handoffs_path, as: :json
    assert_response :created, response.body
    @session_row = @signed_in_session
    token = json["url"].split("/").last
    assert json["url"].start_with?("https://fundtogether.test/wallet/handoff/")
    cookies.delete("session_id")
    token
  end

  def redeem(token)
    post wallet_handoff_path(token), as: :json
  end

  test "the token is stored only as a hash" do
    token = issue_token
    assert_not WalletChallenge.exists?(nonce: token)
    challenge = WalletChallenge.find_by!(nonce: Digest::SHA256.hexdigest(token))
    assert_equal "handoff", challenge.purpose
    assert_operator challenge.expires_at, :<=, 5.minutes.from_now
  end

  test "looking at a handoff does not spend it" do
    token = issue_token
    2.times do
      get wallet_handoff_path(token), as: :json
      assert_response :ok
      assert_equal @user.display_name, json["name"]
    end
    redeem(token)
    assert_response :created
  end

  test "single use" do
    token = issue_token
    redeem(token)
    assert_response :created
    redeem(token)
    assert_response :not_found
    assert_equal "handoff_invalid", json["error"]
    get wallet_handoff_path(token), as: :json
    assert_response :not_found
  end

  test "short lived" do
    token = issue_token
    travel 6.minutes do
      redeem(token)
      assert_response :not_found
    end
  end

  test "unknown and malformed tokens" do
    [ "x", "a" * 43, "a" * 500 ].each do |token|
      redeem(token)
      assert_response :not_found, token
    end
  end

  test "a handoff allows linking" do
    token = issue_token
    redeem(token)
    address = address_of(:alice)
    post wallet_challenges_path, params: { address: address, purpose: "link" }, as: :json
    assert_response :created, response.body
    data = json
    post wallets_path, params: { address: address, nonce: data["nonce"], signature: sign_personal(:alice, data["message"]) }, as: :json
    assert_response :created, response.body
    assert @user.wallets.active.exists?(address: address)
  end

  # Narrowed in stage F: no signing page uses the grant, so a leaked link opens less. On a phone you log in instead.
  test "a handoff allows linking a wallet and nothing else" do
    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    @fake.owners = [ address_of(:alice) ]
    link_wallet(@user, :alice)
    proposal = Chain::ProposalCreator.new(account: @fund, proposer: @user)
                                     .call(kind: "transfer_token", title: "Betaling", params: { "recipient" => address_of(:bob), "amount" => "1" })
    token = issue_token
    redeem(token)

    refused = [
      -> { get account_proposal_path(@fund, proposal), as: :json },
      -> { post account_proposal_signatures_path(@fund, proposal), params: { signature: sign_hash(:alice, proposal.safe_tx_hash) }, as: :json },
      -> { get wallets_path, as: :json },
      -> { delete wallet_path(1), as: :json },
      -> { post wallet_handoffs_path, as: :json },
      -> { get account_proposals_path(@fund), as: :json },
      -> { post account_proposals_path(@fund), params: { kind: "transfer_token", title: "x", params: {} }, as: :json },
      -> { post account_proposal_execution_path(@fund, proposal), params: { tx_hash: "0x#{'a' * 64}" }, as: :json },
      -> { get account_safe_path(@fund), as: :json },
      -> { post account_safe_path(@fund), params: {}, as: :json },
      -> { post account_sync_requests_path(@fund), as: :json },
      -> { get account_chain_events_path(@fund), as: :json },
      -> { get account_balance_path(@fund), as: :json }
    ]
    refused.each_with_index do |request, index|
      request.call
      assert_response :unauthorized, "route #{index}"
    end

    [ dashboard_path, settings_path, users_path ].each do |path|
      get path
      assert_redirected_to new_session_path, path
    end
    patch account_path(@fund), params: { account: { name: "Gekaapt" } }
    assert_redirected_to new_session_path
    assert_not_equal "Gekaapt", @fund.reload.name
  end

  test "a handoff grant expires" do
    token = issue_token
    redeem(token)
    travel 16.minutes do
      post wallet_challenges_path, params: { address: address_of(:alice), purpose: "link" }, as: :json
      assert_response :unauthorized
    end
  end

  test "logging out ends the handoff" do
    token = issue_token
    redeem(token)
    @session_row.destroy!
    post wallet_challenges_path, params: { address: address_of(:alice), purpose: "link" }, as: :json
    assert_response :unauthorized
  end

  test "a forged cookie is ignored" do
    issue_token
    cookies["wallet_handoff"] = "1"
    post wallet_challenges_path, params: { address: address_of(:alice), purpose: "link" }, as: :json
    assert_response :unauthorized
  end

  test "issuing is rate limited" do
    sign_in_as @user
    with_counting_rate_limit_store do
      6.times { post wallet_handoffs_path, as: :json }
    end
    assert_response :too_many_requests
  end
end
