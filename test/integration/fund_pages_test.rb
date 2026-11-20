require "test_helper"

# Every page per role and state. The chain is scripted, so these test what the page says for each
# answer, including an outage. Real browser behaviour is checked separately.
class FundPagesTest < ActionDispatch::IntegrationTest
  CSP_BANNED = /\son[a-z]+\s*=\s*["']|\sstyle\s*=\s*["']/i
  # Fixed widths or non-wrapping constructs that overflow 390px when used for content.
  OVERFLOW_RISK = /\b(whitespace-nowrap|w-\[[5-9]\d\dpx\]|min-w-\[[4-9]\d\dpx\]|w-(96|\[100vw\]))\b/

  setup do
    @fund = accounts(:one)
    @admin = users(:one)
    @member = users(:two)
    @viewer = create_user("vera")
    @fund.account_memberships.create!(user: @viewer, role: "viewer")
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.code = "0x"
  end

  teardown { uninstall_fake_rpc }

  def activate!(owners: [ address_of(:alice), address_of(:bob) ], threshold: 2, balance: 12_500_000)
    link_wallet(@admin, :alice)
    link_wallet(@member, :bob)
    @fake.owners = owners
    @fake.threshold = threshold
    @fake.balance = balance
    @fake.code = "0x60"
    activate_safe(@fund, owners: owners, threshold: threshold)
  end

  def make_proposal(kind: "transfer_token", params: { "recipient" => address_of(:carol), "amount" => "1500000" }, proposer: @member)
    Chain::ProposalCreator.new(account: @fund, proposer: proposer).call(kind: kind, title: "Betaal de huur", params: params)
  end

  def assert_clean_page
    assert_response :success
    assert_no_match CSP_BANNED, response.body
    assert_select "script:not([src]):not([nonce]):not([type])", 0
    assert_no_match(/Traceback|undefined method|ActiveRecord::|Chain::/, response.body)
    assert_no_match(%r{&lt;/?(span|div|dd|dt|p)\b}, response.body, "escaped markup is visible as text")
  end

  def event!(kind, amount: nil, user: nil, from: nil, to: nil, finalized: true, log_index: 0)
    @fund.chain_events.create!(chain_id: ChainTestHelper::SEPOLIA, tx_hash: format("0x%064x", rand(1 << 64)), log_index: log_index,
                               block_number: 1000 + log_index, block_hash: FakeRpc.block_hash(1000), kind: kind, from_address: from,
                               to_address: to, token_address: amount && @fund.token_address, amount: amount, occurred_at: Time.current,
                               finalized: finalized, user: user)
  end

  # --- Access

  test "a non-member gets a 404 on every fund page, the same as a missing fund" do
    activate!
    sign_in_as create_user("nora")
    [ account_invite_path(@fund), account_safe_setup_path(@fund), account_contribute_path(@fund), account_activity_path(@fund),
      account_transparency_path(@fund), account_proposal_pages_path(@fund), account_live_balance_path(@fund) ].each do |path|
      get path
      assert_response :not_found, path
    end
    get account_contribute_path(id = 999_999)
    assert_response :not_found, id.to_s
  end

  test "pages redirect to login without a session" do
    get account_contribute_path(@fund)
    assert_redirected_to new_session_path
    get wallet_page_path
    assert_redirected_to new_session_path
  end

  test "an inactive membership counts as no membership" do
    @fund.account_memberships.find_by(user: @viewer).update!(active: false)
    sign_in_as @viewer
    get account_activity_path(@fund)
    assert_response :not_found
  end

  # --- Dashboard

  test "dashboard of a draft fund teaches the next steps and shows no amount" do
    sign_in_as @admin
    get dashboard_path
    assert_clean_page
    assert_select "h3", text: "Zo gaat dit fonds van start"
    assert_select "a[href=?]", account_safe_setup_path(@fund)
    assert_no_match(/EURC/, response.body)
    assert_select "[data-testid=testnet-banner]", text: /Testgeld, geen echte waarde/
  end

  test "dashboard of an active fund defers the balance to a frame and shows my contribution from chain events" do
    activate!
    event!("token_in", amount: 2_000_000, user: @admin, from: address_of(:alice), to: @fund.safe_address, log_index: 1)
    event!("token_in", amount: 500_000, user: @admin, from: address_of(:alice), to: @fund.safe_address, finalized: false, log_index: 2)
    sign_in_as @admin
    get dashboard_path
    assert_clean_page
    assert_select "turbo-frame#balance_hero[src=?]", account_live_balance_path(@fund, size: "hero", frame: "balance_hero")
    assert_select "p", text: "2,00 EURC"
    assert_select "p", text: /\+ 0,50 EURC in behandeling/
    assert_select "a[href^='https://sepolia.etherscan.io/tx/0x']", minimum: 2
  end

  test "dashboard shows several funds and the switcher still works" do
    other = accounts(:two)
    other.account_memberships.create!(user: @admin, role: "member")
    sign_in_as @admin
    get dashboard_path
    assert_select "p", text: other.name
    post switch_account_path(other)
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "p", text: /Je bekijkt dit fonds/
    assert_equal other, @admin.reload.current_account
  end

  test "a frame on the dashboard does not switch the current fund" do
    other = accounts(:two)
    other.account_memberships.create!(user: @admin, role: "member")
    @admin.update!(current_account: @fund)
    sign_in_as @admin
    get account_live_balance_path(other), headers: { "Turbo-Frame" => "balance_#{other.id}" }
    assert_response :success
    assert_equal @fund, @admin.reload.current_account
  end

  test "live balance shows amount and time, labelled cache, and never a silent zero" do
    activate!
    sign_in_as @member
    get account_live_balance_path(@fund, size: "hero", frame: "balance_hero")
    assert_clean_page
    assert_match "12,50 EURC", response.body
    assert_match "Rechtstreeks van de blockchain gelezen", response.body

    @fake.fail_with(:all)
    get account_live_balance_path(@fund)
    assert_match "laatst bekende stand", response.body
    assert_match "12,50 EURC", response.body

    @fund.update_columns(balance_cached: nil, balance_cached_at: nil)
    get account_live_balance_path(@fund)
    assert_clean_page
    assert_match "kan nu niet worden opgehaald", response.body
    assert_no_match(/0,00/, response.body)
  end

  test "attention frame lists what needs me and says so when the chain is down" do
    activate!
    proposal = make_proposal
    sign_in_as @admin
    get account_live_attention_path(@fund)
    assert_clean_page
    assert_select "a[href=?]", account_proposal_page_path(@fund, proposal)
    assert_match "Wacht op jou", response.body

    @fake.fail_with(:all)
    get account_live_attention_path(@fund)
    assert_clean_page
    assert_match "Kan nu niet controleren", response.body
  end

  # --- Wizard

  test "new fund: step one explains the fund and leads to inviting, then to setup" do
    sign_in_as @admin
    get new_account_path
    assert_clean_page
    assert_match "ondertekenaars", response.body
    assert_difference("Account.count") { post accounts_path, params: { account: { name: "Vakantie", description: "Augustus" } } }
    fund = Account.order(:id).last
    assert_redirected_to account_invite_path(fund)
    follow_redirect!
    assert_clean_page
    assert_select "a[href=?]", account_safe_setup_path(fund)
    assert_select "form[action=?]", invitations_path
  end

  test "invite page is for admins" do
    sign_in_as @member
    get account_invite_path(@fund)
    assert_redirected_to dashboard_path
  end

  # --- Safe setup

  test "safe setup for an admin lists members with wallets as choices and nudges the others" do
    link_wallet(@admin, :alice)
    sign_in_as @admin
    get account_safe_setup_path(@fund)
    assert_clean_page
    assert_select "input[type=checkbox][value=?]", address_of(:alice)
    assert_select "[data-testid=member-without-wallet]", text: /Test User Two/
    assert_select "[data-testid=member-without-wallet]", text: /Vera/, count: 0
    assert_select "[data-controller='safe-deploy flow-ui'][data-safe-deploy-url-value=?]", account_safe_path(@fund)
    assert_match "goedkeuringen", response.body
  end

  test "safe setup never renders operator endpoints" do
    link_wallet(@admin, :alice)
    sign_in_as @admin
    get account_safe_setup_path(@fund)
    chain = Chain::Registry.default
    assert_includes response.body, CGI.escapeHTML(chain.browser_config.to_json)
    (chain.rpc_urls - chain.public_rpc_urls).each { |url| assert_no_match url, response.body }
  end

  test "safe setup is read-only for members and viewers" do
    [ @member, @viewer ].each do |user|
      sign_in_as user
      get account_safe_setup_path(@fund)
      assert_clean_page
      assert_select "[data-controller~='safe-deploy']", 0
      assert_match "Een admin van dit fonds", response.body
    end
  end

  test "deploying state shows the explorer link and no deposit address" do
    link_wallet(@admin, :alice)
    chain = Chain::Registry.default
    predicted = "0x2222222222222222222222222222222222222222"
    hash = "0x#{'ab' * 32}"
    @fund.update!(chain_id: chain.chain_id, token_address: chain.token.address, safe_address: predicted, safe_salt_nonce: 1,
                  safe_owners: [ address_of(:alice) ], safe_threshold: 1, safe_status: "deploying", deploy_tx_hash: hash)
    sign_in_as @admin
    get account_safe_setup_path(@fund)
    assert_clean_page
    assert_select "a[href=?]", "#{chain.explorer_url}/tx/#{hash}"
    assert_match "Stuur nog geen geld", response.body
    get account_contribute_path(@fund)
    assert_no_match(/#{predicted}/i, response.body)
  end

  test "a failed verification comes back to the form with a retry and no raw error" do
    link_wallet(@admin, :alice)
    chain = Chain::Registry.default
    @fund.update!(chain_id: chain.chain_id, token_address: chain.token.address, safe_address: "0x2222222222222222222222222222222222222222",
                  safe_salt_nonce: 1, safe_owners: [ address_of(:alice) ], safe_threshold: 1, safe_verification_error: "singleton_mismatch")
    sign_in_as @admin
    get account_safe_setup_path(@fund)
    assert_clean_page
    assert_match "vorige poging", response.body
    assert_no_match "singleton_mismatch", response.body
  end

  test "an active fund goes from setup to transparency" do
    activate!
    sign_in_as @admin
    get account_safe_setup_path(@fund)
    assert_redirected_to account_transparency_path(@fund)
  end

  # --- Contribute

  test "contribute: draft has a teaching empty state and no controller" do
    sign_in_as @admin
    get account_contribute_path(@fund)
    assert_clean_page
    assert_select "[data-controller~=contribute]", 0
    assert_match "Hier kan nog niets in", response.body
  end

  test "contribute: member gets the decimal text input, token, network, QR and warning" do
    activate!
    sign_in_as @member
    get account_contribute_path(@fund)
    assert_clean_page
    assert_select "input[data-contribute-target=amount][inputmode=decimal][type=text]"
    assert_select "[data-contribute-safe-address-value=?]", @fund.safe_address
    assert_match "Alleen EURC op Sepolia", response.body
    assert_includes response.body, Chain::Address.checksum(@fund.safe_address)
    assert_select "svg[role=img]"
    assert_select "turbo-frame#contribute_recent"
  end

  test "contribute: viewer sees the address but cannot act" do
    activate!
    sign_in_as @viewer
    get account_contribute_path(@fund)
    assert_clean_page
    assert_select "[data-controller~=contribute]", 0
    assert_match "leesrechten", response.body
  end

  test "recent contributions come from chain events with their state" do
    activate!
    event!("token_in", amount: 1_000_000, user: @member, from: address_of(:bob), to: @fund.safe_address, finalized: false)
    sign_in_as @member
    get account_contribute_recent_path(@fund)
    assert_clean_page
    assert_match "In behandeling", response.body
    assert_match "1,00 EURC", response.body
  end

  # --- Proposals

  test "proposal list: needs me for an owner, waiting for others, nothing ready without signatures" do
    activate!
    proposal = make_proposal
    sign_in_as @admin
    get list_account_proposal_pages_path(@fund)
    assert_clean_page
    assert_select "a[href=?]", account_proposal_page_path(@fund, proposal)
    assert_match "Wacht op jou", response.body
    assert_match "1,50 EURC", response.body

    sign_in_as @viewer
    get list_account_proposal_pages_path(@fund)
    assert_match "Wacht op anderen", response.body
    assert_no_match "Klaar om uit te voeren", response.body
  end

  test "readiness is live: enough valid signatures against the current threshold" do
    activate!(threshold: 2)
    proposal = make_proposal
    proposal.safe_signatures.create!(signer_address: address_of(:alice), user: @admin, signature: sign_hash(:alice, proposal.safe_tx_hash))
    sign_in_as @member
    get list_account_proposal_pages_path(@fund)
    assert_match "Wacht op jou", response.body

    @fake.threshold = 1
    get list_account_proposal_pages_path(@fund)
    assert_match "Klaar om uit te voeren", response.body
    get live_account_proposal_page_path(@fund, proposal)
    assert_clean_page
    assert_select "[data-controller~='proposal-execute']"
  end

  test "an outage never reads as ready" do
    activate!(threshold: 1)
    proposal = make_proposal
    proposal.safe_signatures.create!(signer_address: address_of(:alice), user: @admin, signature: sign_hash(:alice, proposal.safe_tx_hash))
    @fake.fail_with(:all)
    sign_in_as @member
    get list_account_proposal_pages_path(@fund)
    assert_clean_page
    assert_match "Live status niet beschikbaar", response.body
    assert_no_match "Klaar om uit te voeren", response.body
    get live_account_proposal_page_path(@fund, proposal)
    assert_clean_page
    assert_select "[data-controller~='proposal-execute']", 0
    assert_select "[data-controller~='proposal-sign']", 0
  end

  test "states executed, failed and superseded each read correctly" do
    activate!
    { "executed" => "Uitgevoerd", "failed" => "Mislukt", "superseded" => "Vervallen" }.each_with_index do |(state, label), index|
      proposal = make_proposal(params: { "recipient" => address_of(:carol), "amount" => (1_000_000 + index).to_s })
      proposal.update!(state: state)
      sign_in_as @admin
      get live_account_proposal_page_path(@fund, proposal)
      assert_clean_page
      assert_match label, response.body
      assert_select "[data-controller~='proposal-sign']", 0
    end
  end

  test "new proposal: each kind renders and explains consequences; viewer is refused" do
    activate!
    sign_in_as @admin
    get new_account_proposal_page_path(@fund)
    assert_clean_page
    { "transfer_token" => "definitief", "transfer_native" => "per ongeluk", "add_owner" => "meebeslissen",
      "remove_owner" => "niet meer goedkeuren", "swap_owner" => "kwijtgeraakte", "change_threshold" => "oudere voorstellen" }.each do |kind, phrase|
      get new_account_proposal_page_path(@fund, kind: kind)
      assert_clean_page
      assert_match phrase, response.body, kind
    end
    sign_in_as @viewer
    get new_account_proposal_page_path(@fund)
    assert_redirected_to dashboard_path
    post account_proposal_pages_path(@fund), params: { kind: "transfer_token", title: "x", recipient: address_of(:carol), amount: "1" }
    assert_redirected_to dashboard_path
    assert_equal 0, @fund.safe_proposals.count
  end

  test "owner forms say so when the chain is down" do
    activate!
    @fake.fail_with(:all)
    sign_in_as @admin
    get new_account_proposal_page_path(@fund, kind: "remove_owner")
    assert_clean_page
    assert_match "Dit kan nu niet", response.body
  end

  # The off-ramp links to the form with ?recipient=. Anyone can craft that URL.
  test "a recipient in the link pre-selects the user's own wallet, says so, and creates nothing" do
    activate!
    sign_in_as @admin
    assert_no_difference -> { @fund.safe_proposals.count } do
      get new_account_proposal_page_path(@fund, kind: "transfer_token", recipient: address_of(:alice))
    end
    assert_clean_page
    assert_select "select[name=recipient_choice] option[selected][value=?]", address_of(:alice)
    assert_select "[data-recipient-link=own]", text: Chain::Address.checksum(address_of(:alice))
    assert_select "input[name=amount]" do |inputs|
      assert_nil inputs.first["value"], "the amount stays empty"
    end
  end

  test "a recipient in the link that is someone else's member wallet is selected and flagged as not yours" do
    activate!
    sign_in_as @admin
    get new_account_proposal_page_path(@fund, kind: "transfer_token", recipient: address_of(:bob))
    assert_clean_page
    assert_select "select[name=recipient_choice] option[selected][value=?]", address_of(:bob)
    assert_select "[data-recipient-link=other]", text: Chain::Address.checksum(address_of(:bob))
  end

  test "a recipient in the link that is no member goes in the free address field, with a warning, shown in full" do
    activate!
    sign_in_as @admin
    get new_account_proposal_page_path(@fund, kind: "transfer_token", recipient: address_of(:carol))
    assert_clean_page
    assert_select "select[name=recipient_choice] option[selected][value=other]"
    assert_select "input[name=recipient][value=?]", address_of(:carol)
    assert_select "[data-recipient-link=other]", text: Chain::Address.checksum(address_of(:carol))
  end

  test "garbage or a bad checksum in the link fills in nothing" do
    activate!
    sign_in_as @admin
    [ "<script>alert(1)</script>", "0x1234", address_of(:carol).sub(/[a-f]/, &:upcase) ].each do |bad|
      get new_account_proposal_page_path(@fund, kind: "transfer_token", recipient: bad)
      assert_clean_page
      assert_select "[data-recipient-link=invalid]"
      assert_select "input[name=recipient]" do |inputs|
        assert_nil inputs.first["value"], bad
      end
      assert_no_match "alert(1)", response.body
    end
  end

  test "owner forms ignore a recipient in the link" do
    activate!
    sign_in_as @admin
    get new_account_proposal_page_path(@fund, kind: "change_threshold", recipient: address_of(:carol))
    assert_clean_page
    assert_select "[data-recipient-link]", 0
  end

  test "a refused post keeps what the user typed, without the notice about a link" do
    activate!
    sign_in_as @admin
    post account_proposal_pages_path(@fund), params: { kind: "transfer_token", title: "Huur", recipient_choice: "other", recipient: address_of(:carol), amount: "nope" }
    assert_response :unprocessable_entity
    assert_select "input[name=recipient][value=?]", address_of(:carol)
    assert_select "[data-recipient-link]", 0
  end

  test "pay out form converts a Dutch decimal to base units without a float" do
    activate!
    sign_in_as @admin
    post account_proposal_pages_path(@fund), params: { kind: "transfer_token", title: "Huur", recipient_choice: "other",
                                                       recipient: address_of(:carol), amount: "1234,567891" }
    proposal = @fund.safe_proposals.last
    assert_redirected_to account_proposal_page_path(@fund, proposal)
    assert_equal "1234567891", proposal.params["amount"]
    assert_equal address_of(:carol), proposal.params["recipient"]
    follow_redirect!
    assert_clean_page
    assert_match "1.234,567891 EURC", response.body
    assert_includes response.body, Chain::Address.checksum(address_of(:carol))
    assert_includes response.body, proposal.safe_tx_hash
  end

  test "pay out form refuses bad input in Dutch and keeps what was typed" do
    activate!
    sign_in_as @admin
    { "1,1234567" => "te veel cijfers", "abc" => "geldig bedrag", "0" => "groter dan nul" }.each do |amount, message|
      post account_proposal_pages_path(@fund), params: { kind: "transfer_token", title: "Huur", recipient_choice: "other",
                                                         recipient: address_of(:carol), amount: amount }
      assert_response :unprocessable_entity
      assert_match message, response.body
      assert_select "input[name=amount][value=?]", amount
    end
    post account_proposal_pages_path(@fund), params: { kind: "transfer_token", title: "Huur", recipient_choice: "other", recipient: "nope", amount: "1" }
    assert_response :unprocessable_entity
    assert_match "geen geldig adres", response.body
    assert_equal 0, @fund.safe_proposals.count
  end

  test "owner change forms create typed proposals and enforce the risk acknowledgement" do
    activate!
    sign_in_as @admin
    post account_proposal_pages_path(@fund), params: { kind: "change_threshold", title: "Eén is genoeg", threshold: "1" }
    assert_response :unprocessable_entity
    assert_match "risico", response.body

    post account_proposal_pages_path(@fund), params: { kind: "change_threshold", title: "Eén is genoeg", threshold: "1", acknowledge_risk: "1" }
    proposal = @fund.safe_proposals.last
    assert_redirected_to account_proposal_page_path(@fund, proposal)
    assert_equal 1, proposal.params["threshold"]
    get account_proposal_page_path(@fund, proposal)
    assert_clean_page
  end

  test "detail page: decoded action and hash up front, live progress and signing in the frame" do
    activate!
    proposal = make_proposal
    sign_in_as @admin
    get account_proposal_page_path(@fund, proposal)
    assert_clean_page
    assert_match "1,50 EURC", response.body
    assert_includes response.body, proposal.safe_tx_hash
    assert_match "vingerafdruk", response.body
    assert_select "turbo-frame#proposal_live"

    get live_account_proposal_page_path(@fund, proposal)
    assert_clean_page
    assert_match "0 van 2", response.body
    assert_select "[data-controller~='proposal-sign'][data-proposal-sign-signatures-url-value=?]", account_proposal_signatures_path(@fund, proposal)
    assert_select "[data-proposal-sign-target=field][data-field=safeTxHash]"
    assert_select "form[action=?]", reject_account_proposal_page_path(@fund, proposal)
  end

  test "reject creates a rejection at the same nonce" do
    activate!
    proposal = make_proposal
    sign_in_as @admin
    post reject_account_proposal_page_path(@fund, proposal)
    rejection = @fund.safe_proposals.where(kind: "rejection").last
    assert_redirected_to account_proposal_page_path(@fund, rejection)
    assert_equal proposal.nonce, rejection.nonce
    get live_account_proposal_page_path(@fund, proposal)
    assert_match "hetzelfde volgnummer", response.body
  end

  test "the owner forms govern their own submit button, and swap has nothing to submit without a new wallet" do
    activate!
    sign_in_as @admin
    %w[add_owner remove_owner change_threshold].each do |kind|
      get new_account_proposal_page_path(@fund, kind: kind)
      assert_select "form[data-controller=threshold] button[data-threshold-target=submit]", 1, kind
    end
    get new_account_proposal_page_path(@fund, kind: "swap_owner")
    assert_select "form[data-controller=threshold]", 0
    assert_select "button[type=submit][disabled]", 1
  end

  test "the users page shows gaps without the approvals list" do
    activate!
    make_proposal
    @member.wallets.first.revoke!
    sign_in_as @admin
    get account_live_attention_path(@fund, gaps: "1")
    assert_clean_page
    assert_match "hoort niet meer bij een gekoppelde wallet", response.body
    assert_no_match "Wacht op jou", response.body
  end

  test "a viewer sees a proposal but no sign, execute or reject" do
    activate!
    proposal = make_proposal
    sign_in_as @viewer
    get live_account_proposal_page_path(@fund, proposal)
    assert_clean_page
    assert_select "[data-controller~='proposal-sign']", 0
    assert_select "form[action=?]", reject_account_proposal_page_path(@fund, proposal), 0
    assert_match "geen ondertekenaar", response.body
    post reject_account_proposal_page_path(@fund, proposal)
    assert_redirected_to dashboard_path
  end

  test "proposal of another fund is a 404" do
    activate!
    proposal = make_proposal
    other = accounts(:two)
    other.account_memberships.create!(user: @admin, role: "admin")
    activate_safe(other, owners: [ address_of(:alice) ], threshold: 1, safe: "0x4444444444444444444444444444444444444444")
    sign_in_as @admin
    get account_proposal_page_path(other, proposal)
    assert_response :not_found
  end

  test "proposal pages on a draft fund send you to setup" do
    sign_in_as @admin
    get account_proposal_pages_path(@fund)
    assert_redirected_to account_safe_setup_path(@fund)
  end

  # --- Activity

  test "activity: rows with explorer links, member totals, unknown senders, filter and CSV" do
    activate!
    event!("token_in", amount: 3_000_000, user: @member, from: address_of(:bob), to: @fund.safe_address, log_index: 1)
    event!("token_in", amount: 7_000_000, from: address_of(:carol), to: @fund.safe_address, log_index: 2)
    event!("token_out", amount: 1_000_000, from: @fund.safe_address, to: address_of(:bob), log_index: 3)
    event!("owner_added", to: address_of(:bob), log_index: 4)
    sign_in_as @viewer
    get account_activity_path(@fund)
    assert_clean_page
    assert_select "a[href^='https://sepolia.etherscan.io/tx/0x']", 4
    assert_match "Onbekende afzender", response.body
    assert_match "7,00 EURC", response.body
    assert_select "span", text: "Test User Two"
    assert_select "a[href=?]", account_chain_events_path(@fund, format: :csv)

    get account_activity_path(@fund, filter: "out")
    assert_select "a[href^='https://sepolia.etherscan.io/tx/0x']", 1

    get account_activity_path(@fund, member: "unknown")
    assert_select "a[href^='https://sepolia.etherscan.io/tx/0x']", 1

    get account_chain_events_path(@fund, format: :csv)
    assert_response :success
    assert_match "tx_hash", response.body
  end

  test "activity: the member filter cannot reach users outside the fund" do
    activate!
    outsider = create_user("otto")
    event!("token_in", amount: 1, user: outsider, from: address_of(:carol), to: @fund.safe_address)
    sign_in_as @member
    get account_activity_path(@fund, member: outsider.id)
    assert_select "a[href^='https://sepolia.etherscan.io/tx/0x']", 0
  end

  test "activity: empty and draft states teach" do
    sign_in_as @admin
    get account_activity_path(@fund)
    assert_clean_page
    assert_match "Nog geen activiteit", response.body
    activate!
    get account_activity_path(@fund)
    assert_clean_page
    assert_match "De eerste inleg", response.body
  end

  # --- Transparency and gaps

  test "transparency: address, chain, token, Safe{Wallet} link and exit explanation" do
    activate!
    sign_in_as @viewer
    get account_transparency_path(@fund)
    assert_clean_page
    assert_includes response.body, Chain::Address.checksum(@fund.safe_address)
    assert_select "a[href=?]", "https://app.safe.global/home?safe=sep:#{Chain::Address.checksum(@fund.safe_address)}"
    assert_match "Zonder FundTogether verder", response.body
    assert_match "EURC", response.body
  end

  test "live owners: sentence, names, version and a warning on an unexpected singleton" do
    activate!
    sign_in_as @member
    get account_live_owners_path(@fund)
    assert_clean_page
    assert_match "2 van de 2 moeten goedkeuren", response.body
    assert_match "Test User One", response.body
    assert_match "Safe L2 1.4.1", response.body

    @fake.singleton_address = "0x5555555555555555555555555555555555555555"
    get account_live_owners_path(@fund)
    assert_match "Onverwacht contract", response.body

    @fake.fail_with(:all)
    get account_live_owners_path(@fund)
    assert_clean_page
    assert_match "Live gegevens zijn nu niet beschikbaar", response.body
  end

  test "removing a member who is an owner prompts a remove_owner proposal and the gap stays visible" do
    activate!
    sign_in_as @admin
    delete user_path(@member), params: { account_id: @fund.id }
    bob = address_of(:bob)
    assert_redirected_to new_account_proposal_page_path(@fund, kind: "remove_owner", owner: bob)
    assert_match "kan op de blockchain nog steeds goedkeuren", flash[:warning]
    follow_redirect!
    assert_clean_page
    assert_select "select[name=owner] option[selected][value=?]", bob

    get account_live_attention_path(@fund)
    assert_match "is geen lid meer, maar kan nog goedkeuren", response.body
    assert_select "a[href=?]", new_account_proposal_page_path(@fund, kind: "remove_owner", owner: bob)
  end

  test "an owner whose wallet was unlinked shows as a gap with a swap offer" do
    activate!
    @member.wallets.first.revoke!
    sign_in_as @admin
    get account_live_owners_path(@fund)
    assert_match "hoort niet meer bij een gekoppelde wallet", response.body
    assert_select "a[href=?]", new_account_proposal_page_path(@fund, kind: "swap_owner", old_owner: address_of(:bob))
  end

  test "only an admin can remove a member, and not themselves" do
    sign_in_as @member
    delete user_path(@admin), params: { account_id: @fund.id }
    assert_redirected_to dashboard_path
    assert @fund.account_memberships.active.exists?(user: @admin)
    sign_in_as @admin
    delete user_path(@admin), params: { account_id: @fund.id }
    assert_redirected_to users_path(account_id: @fund.id)
    assert @fund.account_memberships.active.exists?(user: @admin)
    delete user_path(create_user("nora")), params: { account_id: @fund.id }
    assert_match "niet gevonden", flash[:alert]
  end

  # --- Wallets

  test "wallets page: empty, guide with the never-share warning, and no seed phrase input" do
    sign_in_as @admin
    get wallet_page_path
    assert_clean_page
    assert_match "Nog geen wallet?", response.body
    assert_match "Deel je herstelzin nooit", response.body
    assert_match "Rabby", response.body
    assert_match "MetaMask", response.body
    assert_select "[data-controller~='wallet-link'][data-wallet-link-challenges-url-value=?]", wallet_challenges_path
    assert_select "textarea", 0
  end

  test "wallets page lists wallets; ownership is live; unlink warns and is scoped to me" do
    activate!
    sign_in_as @admin
    wallet = @admin.wallets.first
    get wallet_page_path
    assert_clean_page
    assert_includes response.body, Chain::Address.checksum(wallet.address)
    assert_match "Dit verandert niets op de blockchain", response.body

    get wallet_page_ownership_path(wallet)
    assert_clean_page
    assert_match "Ondertekenaar van", response.body

    @fake.fail_with(:all)
    get wallet_page_ownership_path(wallet)
    assert_match "Kon nu niet controleren", response.body
    @fake.heal!

    delete wallet_page_unlink_path(@member.wallets.first)
    assert_match "niet gevonden", flash[:alert]
    assert @member.wallets.first.active?

    delete wallet_page_unlink_path(wallet)
    assert_redirected_to wallet_page_path
    assert_match "blijft hij ondertekenaar", flash[:warning]
    assert_not wallet.reload.active?
  end

  test "QR handoff is server rendered as a turbo stream and stores only a hash" do
    sign_in_as @admin
    assert_difference("WalletChallenge.where(purpose: 'handoff').count") do
      post wallet_page_handoff_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_match "turbo-stream", response.body
    assert_includes response.body, "<svg", "expected an inline SVG QR"
    assert_no_match CSP_BANNED, response.body
    token = response.body[%r{/wallet/handoff/([A-Za-z0-9_-]+)}, 1]
    assert token
    assert_nil WalletChallenge.find_by(nonce: token)
  end

  # --- Handoff pages

  def issue_handoff_token
    sign_in_as @admin
    post wallet_handoffs_path, as: :json
    token = json["url"].split("/").last
    cookies.delete("session_id")
    token
  end

  test "handoff confirmation page shows the name and does not spend the token, even when fetched twice" do
    token = issue_handoff_token
    2.times do
      get wallet_handoff_path(token)
      assert_clean_page
      assert_select "h1", text: /Test User One/
      assert_select "form[action=?][method=post]", wallet_handoff_path(token)
    end
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_not WalletChallenge.find_handoff(token).consumed?
  end

  test "handoff: a HEAD or preview fetch cannot spend it; a POST does and gives the linking page" do
    token = issue_handoff_token
    head wallet_handoff_path(token)
    assert_not WalletChallenge.find_handoff(token).consumed?

    post wallet_handoff_path(token)
    assert_redirected_to wallet_handoff_path(token)
    assert WalletChallenge.find_handoff(token).consumed?
    follow_redirect!
    assert_clean_page
    assert_select "[data-controller~='wallet-link']"
    assert_select "button[data-action='wallet-link#link']"
    assert_select "aside", 0, "the wallet browser must not get the app menu"
  end

  test "handoff: a second browser with the same link gets a friendly dead end" do
    token = issue_handoff_token
    post wallet_handoff_path(token)
    cookies.delete("wallet_handoff")
    get wallet_handoff_path(token)
    assert_response :not_found
    assert_match "werkt niet meer", response.body
    post wallet_handoff_path(token)
    assert_response :not_found
  end

  test "handoff: an expired or unknown token shows Dutch text, not JSON" do
    token = issue_handoff_token
    WalletChallenge.find_handoff(token).update!(expires_at: 1.minute.ago)
    get wallet_handoff_path(token)
    assert_response :not_found
    assert_match "werkt niet meer", response.body
    get wallet_handoff_path("onzin")
    assert_response :not_found
    assert_match "text/html", response.content_type
  end

  test "handoff: the confirmation POST is CSRF protected" do
    token = issue_handoff_token
    with_forgery_protection do
      post wallet_handoff_path(token)
      assert_response :not_found
      assert_match "Vernieuw de pagina", response.body
    end
    assert_not WalletChallenge.find_handoff(token).consumed?
  end

  def with_forgery_protection
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "256-bit values can be written and queried when prepared statements are off" do
    big = 2**200
    Account.connection.unprepared_statement do
      @fund.update!(safe_salt_nonce: big)
      assert Account.where(safe_salt_nonce: big).exists?
    end
    assert_equal big, @fund.reload.safe_salt_nonce.to_i
  end

  # --- Home, layout, nav

  test "home makes no false claims and says what it does not do" do
    get root_path
    assert_clean_page
    assert_match "Wat FundTogether niet doet", response.body
    assert_no_match(/Monerium EURe fiat integratie|Coinbase Wallet|WalletConnect|Verbind Wallet/, response.body)
    assert_match "Testgeld, geen echte waarde", response.body
  end

  test "sidebar links to every section including the ramp" do
    sign_in_as @admin
    get dashboard_path
    [ account_contribute_path(@fund), account_proposal_pages_path(@fund), account_activity_path(@fund), account_ramp_path(@fund),
      account_transparency_path(@fund), wallet_page_path, users_path, settings_path ].each do |path|
      assert_select "aside a[href=?]", path
    end
    assert_select "aside a", text: "Geld storten/opnemen"
  end

  test "no testnet banner on a mainnet fund" do
    link_wallet(@admin, :alice)
    base = Chain::Registry.all.fetch("base")
    previous = ENV["FUNDTOGETHER_CHAINS"]
    ENV["FUNDTOGETHER_CHAINS"] = "sepolia,base"
    @fake = install_fake_rpc(FakeRpc.new(chain: base))
    @fake.owners = [ address_of(:alice) ]
    @fund.update!(chain_id: base.chain_id, token_address: base.token.address, safe_address: "0x6666666666666666666666666666666666666666",
                  safe_salt_nonce: 1, safe_status: "active", safe_owners: [ address_of(:alice) ], safe_threshold: 1)
    sign_in_as @admin
    get dashboard_path
    assert_select "[data-testid=testnet-banner]", 0
  ensure
    ENV["FUNDTOGETHER_CHAINS"] = previous
  end

  test "a fund on a chain the operator switched off keeps working pages, not a crash" do
    activate!
    @fund.update_columns(chain_id: 8453)
    sign_in_as @admin
    get dashboard_path
    assert_clean_page
    assert_match "Netwerk niet beschikbaar", response.body
    get account_contribute_path(@fund)
    assert_redirected_to dashboard_path
  end

  test "users and settings have no phone overflow traps, for each role" do
    [ @admin, @member, @viewer ].each do |user|
      sign_in_as user
      [ users_path, settings_path ].each do |path|
        get path
        assert_clean_page
        assert_no_match OVERFLOW_RISK, response.body, path
      end
    end
  end

  test "no template uses a construct that forces horizontal overflow on a phone" do
    offenders = Rails.root.glob("app/views/**/*.erb").reject { |path| path.to_s.match?(/mailer|ramps/) }.select do |path|
      path.read.match?(OVERFLOW_RISK)
    end
    assert_empty offenders.map { |path| path.relative_path_from(Rails.root).to_s }
  end

  test "the main column can shrink below its content, which is what prevents overflow on a phone" do
    sign_in_as @admin
    get dashboard_path
    assert_select "main.min-w-0"
  end

  test "hashes and addresses in templates wrap" do
    sign_in_as @admin
    activate!
    get account_transparency_path(@fund)
    assert_select ".font-mono.break-hash", minimum: 1
  end
end
