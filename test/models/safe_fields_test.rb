require "test_helper"

class SafeFieldsTest < ActiveSupport::TestCase
  ALICE = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf".freeze

  setup { @fund = accounts(:one) }

  test "a new fund is a draft, and a draft can be destroyed" do
    assert_equal "draft", @fund.safe_status
    assert_predicate @fund.safe_group_uuid, :present?
    assert @fund.destroy
  end

  %w[deploying active].each do |status|
    test "a #{status} fund refuses destroy, in Dutch" do
      activate_safe(@fund, owners: [ ALICE ], threshold: 1)
      @fund.update!(safe_status: status)
      @fund.account_memberships.count.then do |memberships|
        assert_not @fund.destroy
        assert_equal memberships, @fund.account_memberships.reload.count, "dependents were destroyed"
      end
      assert_match(/kan niet worden verwijderd/, @fund.errors[:base].first)
      assert Account.exists?(@fund.id)
    end

    test "chain and token cannot change when #{status}" do
      activate_safe(@fund, owners: [ ALICE ], threshold: 1)
      @fund.update!(safe_status: status)
      %i[chain_id token_address safe_address safe_threshold].each do |field|
        fund = Account.find(@fund.id)
        fund[field] = field == :chain_id ? 8453 : (field == :safe_threshold ? 9 : ALICE)
        assert_not fund.save, "#{field} changed"
        assert_predicate fund.errors[field], :present?
      end
    end
  end

  test "settings can change while draft" do
    assert @fund.update(chain_id: 11_155_111, token_address: ALICE)
    assert @fund.update(chain_id: 8453)
  end

  test "the database refuses mixed case and bad states" do
    [ { token_address: "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf" }, { safe_address: "0x12" }, { safe_status: "gekaapt" },
      { deploy_tx_hash: "0x12" }, { safe_status: "active" } ].each do |bad|
      assert_raises(ActiveRecord::StatementInvalid, bad.to_s) do
        Account.transaction(requires_new: true) { @fund.update_columns(bad) }
      end
    end
  end

  test "safe address is unique per chain" do
    activate_safe(@fund, owners: [ ALICE ], threshold: 1)
    other = accounts(:two)
    assert_not other.update(chain_id: @fund.chain_id, safe_address: @fund.safe_address)
    assert_raises(ActiveRecord::RecordNotUnique) do
      other.update_columns(chain_id: @fund.chain_id, safe_address: @fund.safe_address)
    end
  end

  test "numeric(78,0) holds a full uint256 exactly" do
    max = (2**256) - 1
    @fund.update!(safe_salt_nonce: max)
    assert_equal max, Account.find(@fund.id).safe_salt_nonce.to_i
  end

  test "one active user per address, relinking allowed after revoke" do
    first = users(:one).wallets.create!(address: ALICE, verified_at: Time.current)
    assert_raises(ActiveRecord::RecordNotUnique) { users(:two).wallets.create!(address: ALICE, verified_at: Time.current) }
    first.revoke!
    assert users(:two).wallets.create!(address: ALICE, verified_at: Time.current)
  end

  test "wallet addresses are stored lowercase" do
    wallet = users(:one).wallets.create!(address: ALICE.upcase.sub("0X", "0x"), verified_at: Time.current)
    assert_equal ALICE, wallet.address
    assert_raises(ActiveRecord::StatementInvalid) { wallet.update_columns(kind: "contract") }
  end

  test "wallet active_at is a window between verified and revoked" do
    wallet = users(:one).wallets.create!(address: ALICE, verified_at: 10.days.ago, revoked_at: 5.days.ago)
    assert_includes Wallet.active_at(7.days.ago), wallet
    assert_not_includes Wallet.active_at(11.days.ago), wallet
    assert_not_includes Wallet.active_at(1.day.ago), wallet
  end

  test "proposal fields and database constraints" do
    activate_safe(@fund, owners: [ ALICE ], threshold: 1)
    attributes = { proposer: users(:one), kind: "rejection", title: "Stop", to: @fund.safe_address, data: "0x", nonce: 2**200, safe_tx_hash: "0x#{'a' * 64}" }
    proposal = @fund.safe_proposals.create!(attributes)
    assert_equal 2**200, SafeProposal.find(proposal.id).nonce.to_i

    assert_raises(ActiveRecord::RecordNotUnique) do
      SafeProposal.transaction(requires_new: true) { SafeProposal.new(attributes.merge(account: @fund)).save!(validate: false) }
    end
    { operation: 1, to: "0xABC", data: "nothex", safe_tx_hash: "x", kind: "exec", state: "ready" }.each do |field, value|
      assert_raises(ActiveRecord::StatementInvalid, field.to_s) do
        SafeProposal.transaction(requires_new: true) { SafeProposal.where(id: proposal.id).update_all(field => value) }
      end
    end
  end

  test "what was hashed cannot be changed through the model" do
    activate_safe(@fund, owners: [ ALICE ], threshold: 1)
    proposal = @fund.safe_proposals.create!(proposer: users(:one), kind: "rejection", title: "Stop", to: @fund.safe_address, data: "0x", nonce: 1, safe_tx_hash: "0x#{'a' * 64}")
    %i[to data nonce safe_tx_hash kind params].each do |field|
      assert_raises(ActiveRecord::ReadonlyAttributeError, field.to_s) { proposal.update(field => "x") }
    end
  end

  test "signature rows are unique per signer and canonical" do
    activate_safe(@fund, owners: [ ALICE ], threshold: 1)
    proposal = @fund.safe_proposals.create!(proposer: users(:one), kind: "rejection", title: "Stop", to: @fund.safe_address, data: "0x", nonce: 1, safe_tx_hash: "0x#{'a' * 64}")
    signature = "0x#{'a' * 128}1b"
    proposal.safe_signatures.create!(signer_address: ALICE, signature: signature, user: users(:one))
    assert_raises(ActiveRecord::RecordNotUnique) do
      SafeSignature.transaction(requires_new: true) { SafeSignature.new(safe_proposal: proposal, signer_address: ALICE, signature: signature, user: users(:one)).save!(validate: false) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      SafeSignature.new(safe_proposal: proposal, signer_address: "0x#{'b' * 40}", signature: "0x#{'a' * 128}00", user: users(:one)).save!(validate: false)
    end
  end
end
