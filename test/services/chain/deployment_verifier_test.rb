require "test_helper"

class ChainDeploymentVerifierTest < ActiveSupport::TestCase
  setup do
    @fund = accounts(:one)
    @owners = Chain::Address.sort([ address_of(:alice), address_of(:bob) ])
    @fake = install_fake_rpc(FakeRpc.new)
    activate_safe(@fund, owners: @owners, threshold: 2)
    @fund.update_columns(safe_status: "deploying")
    @fake.owners = @owners
    @fake.threshold = 2
  end

  teardown { uninstall_fake_rpc }

  def verify
    Chain::DeploymentVerifier.new(@fund).call
  end

  test "activates when everything matches" do
    result = verify
    assert_predicate result, :verified?
    assert_predicate @fund.reload, :safe_active?
    assert_predicate @fund.safe_verified_at, :present?
  end

  {
    "singleton_mismatch" => ->(fake) { fake.singleton_address = "0x41675c099f32341bf84bfc5382af534df5c7461a" },
    "owners_mismatch" => ->(fake) { fake.owners = [ fake.owners.first ] },
    "threshold_mismatch" => ->(fake) { fake.threshold = 1 },
    "modules_present" => ->(fake) { fake.modules_list = [ "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf" ] },
    "guard_present" => ->(fake) { fake.guard_address = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf" },
    "fallback_handler_mismatch" => ->(fake) { fake.fallback_address = Chain::Address::ZERO }
  }.each do |code, tamper|
    test "refuses on #{code}" do
      tamper.call(@fake)
      result = verify
      assert_not_predicate result, :verified?
      assert_includes result.failures, code
      assert_predicate @fund.reload, :safe_deploying?
      assert_equal code, @fund.safe_verification_error
    end
  end

  test "owner order is part of identity" do
    @fake.owners = @owners.reverse
    assert_includes verify.failures, "owners_mismatch"
  end

  test "no code yet leaves it waiting" do
    @fake.code = "0x"
    result = verify
    assert_equal [ "no_code" ], result.failures
    assert_predicate @fund.reload, :safe_deploying?
  end

  test "a transaction that vanished returns to draft after a day" do
    @fake.code = "0x"
    @fund.update_columns(deploy_tx_hash: "0x#{'a' * 64}", updated_at: 25.hours.ago)
    verify
    assert_predicate @fund.reload, :safe_draft?
    assert_equal "deploy_tx_not_found", @fund.safe_verification_error
  end

  test "RPC failure raises instead of deciding" do
    @fake.fail_with(:get_code)
    assert_raises(Chain::Rpc::Error) { verify }
    assert_predicate @fund.reload, :safe_deploying?

    @fake.heal!
    @fake.fail_with(:eth_call)
    assert_raises(Chain::Rpc::Error) { verify }
    assert_predicate @fund.reload, :safe_deploying?
  end

  test "the job verifies deploying funds, and only those" do
    SafeDeploymentVerificationJob.perform_now(@fund.id)
    assert_predicate @fund.reload, :safe_active?
    SafeDeploymentVerificationJob.perform_now(0)
  end
end
