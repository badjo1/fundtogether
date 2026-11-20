require "test_helper"

# Every row of the file the JS suite also asserts.
class SafeVectorsTest < ActiveSupport::TestCase
  def tx_fields(row)
    { to: row["to"], value: row["value"].to_i, data: row["data"], operation: row["operation"],
      safe_tx_gas: row["safe_tx_gas"].to_i, base_gas: row["base_gas"].to_i, gas_price: row["gas_price"].to_i,
      gas_token: row["gas_token"], refund_receiver: row["refund_receiver"], nonce: row["nonce"].to_i }
  end

  test "type hashes, selectors, topics and proxy code" do
    constants = vectors["constants"]
    assert_equal constants["domain_typehash"], Chain::Eip712::DOMAIN_TYPEHASH
    assert_equal constants["safe_tx_typehash"], Chain::Eip712::SAFE_TX_TYPEHASH
    constants["selectors"].each_value { |row| assert_equal row["selector"], Chain::Abi.selector_hex(row["signature"]) }
    constants["topics"].each_value { |row| assert_equal row["topic"], Chain::Hex.from_bin(Chain::Hex.keccak(row["signature"])) }
    assert_equal constants["proxy_creation_code"], Chain::Create2::PROXY_CREATION_CODE
    assert_equal constants["proxy_creation_code_keccak"], Chain::Hex.keccak_hex(Chain::Create2::PROXY_CREATION_CODE)
    assert_equal constants["guard_slot"], Chain::SafeReader::GUARD_SLOT
    assert_equal constants["fallback_slot"], Chain::SafeReader::FALLBACK_SLOT
    sepolia = Chain::Registry.all.fetch("sepolia")
    assert_equal constants["singleton_l2"], sepolia.singleton
    assert_equal constants["factory"], sepolia.factory
    assert_equal constants["fallback_handler"], sepolia.fallback_handler
  end

  test "test key addresses" do
    vectors["test_keys"].each_with_index do |row, index|
      assert_equal row["address"], address_of(%i[alice bob carol dave][index])
    end
  end

  test "safe tx hashes, including real Gnosis transactions" do
    rows = vectors["safe_tx_hashes"]
    assert_operator rows.count { |row| row["tx_hash"] }, :>=, 2
    rows.each do |row|
      fields = tx_fields(row)
      assert_equal row["domain_separator"], Chain::Eip712.domain_separator(chain_id: row["chain_id"], safe: row["safe"]), row["name"]
      assert_equal row["struct_hash"], Chain::Eip712.struct_hash(**fields), row["name"]
      assert_equal row["safe_tx_hash"], Chain::Eip712.safe_tx_hash(chain_id: row["chain_id"], safe: row["safe"], **fields), row["name"]
    end
  end

  test "create2 predictions and initializers, including real deployments" do
    rows = vectors["create2"]
    assert_operator rows.count { |row| row["tx_hash"] }, :>=, 2
    rows.each do |row|
      prediction = Chain::Create2.predict(factory: row["factory"], singleton: row["singleton"],
                                          initializer: row["initializer"], salt_nonce: row["salt_nonce"].to_i)
      assert_equal row["predicted_address"], prediction, row["name"]
      next unless row["group_uuid"]

      assert_equal row["initializer"], Chain::Create2.initializer(owners: row["owners"], threshold: row["threshold"],
                                                                  fallback_handler: row["fallback_handler"]), row["name"]
      assert_equal row["salt_nonce"], Chain::Create2.salt_nonce(group_uuid: row["group_uuid"], chain_id: row["chain_id"]).to_s, row["name"]
    end
  end

  def build(row)
    context = row["context"]
    Chain::ProposalBuilder.build(kind: row["kind"], params: row["params"], safe: context["safe"], token: context["token"],
                                 owners: context["owners"], threshold: context["threshold"],
                                 current_nonce: context["current_nonce"].to_i)
  end

  test "calldata built from typed parameters" do
    vectors["calldata"].each do |row|
      built = build(row)
      expected = row["expected"]
      assert_equal expected["to"], built.to, row["name"]
      assert_equal expected["value"], built.value.to_s, row["name"]
      assert_equal expected["data"], built.data, row["name"]
      assert_equal 0, built.operation, row["name"]
      assert_equal row["params"].transform_values(&:to_s), built.params.transform_values(&:to_s), row["name"]
      hash = Chain::Eip712.safe_tx_hash(chain_id: row["context"]["chain_id"], safe: row["context"]["safe"],
                                        to: built.to, value: built.value, data: built.data, operation: 0, nonce: row["nonce"].to_i)
      assert_equal expected["safe_tx_hash"], hash, row["name"]
      assert_nil Chain::SafePolicy.violation({ to: built.to, value: built.value, data: built.data, operation: 0, nonce: row["nonce"] },
                                             safe: row["context"]["safe"], token: row["context"]["token"],
                                             current_nonce: row["context"]["current_nonce"]), row["name"]
    end
  end

  test "typed parameters that must be refused" do
    vectors["build_refusals"].each do |row|
      error = assert_raises(Chain::Refusal, row["name"]) { build(row) }
      assert_equal row["code"], error.code, row["name"]
      assert_predicate error.message, :present?
    end
  end

  test "threshold rules" do
    vectors["threshold_rules"].each do |row|
      if row["code"]
        error = assert_raises(Chain::Refusal, row.to_s) do
          Chain::ThresholdRules.check!(owner_count: row["owner_count"], threshold: row["threshold"], acknowledge_risk: row["acknowledge_risk"])
        end
        assert_equal row["code"], error.code
      else
        assert_nil Chain::ThresholdRules.check!(owner_count: row["owner_count"], threshold: row["threshold"], acknowledge_risk: row["acknowledge_risk"])
      end
    end
  end

  def policy(row)
    Chain::SafePolicy.violation(row["tx"].symbolize_keys, safe: row["context"]["safe"], token: row["context"]["token"],
                                current_nonce: row["context"]["current_nonce"])
  end

  test "policy refusals" do
    vectors["policy_refusals"].each { |row| assert_equal row["code"], policy(row), row["name"] }
  end

  test "policy allows what FundTogether builds" do
    vectors["policy_allowed"].each { |row| assert_nil policy(row), row["name"] }
  end

  test "signature recovery" do
    vectors["signatures"]["recover"].each do |row|
      signer = case row["kind"]
      when "eip712" then Chain::Signature.recover_hash(row["hash"], row["signature"])
      when "personal" then Chain::Signature.recover_personal(row["message"], row["signature"])
      when "safe_eth_sign"
        # On-chain v=31/32: not accepted for FundTogether signing, recovered here only as a
        # real-world check of the curve code.
        digest = Chain::Signature.personal_digest(Chain::Hex.to_bin(row["hash"]))
        plain = row["signature"][0, 130] + format("%02x", row["signature"][130, 2].to_i(16) - 4)
        Chain::Signature.recover_digest(digest, plain)
      end
      assert_equal row["signer"], signer, row["name"]
      assert_equal row["normalized"], Chain::Signature.normalize(row["signature"]), row["name"] if row["normalized"]
    end
  end

  test "signatures that must be refused" do
    vectors["signatures"]["rejected"].each do |row|
      error = assert_raises(Chain::Signature::Invalid, row["name"]) { Chain::Signature.recover_hash(row["hash"], row["signature"]) }
      assert_equal row["code"], error.message, row["name"]
    end
  end

  test "a signature for another hash recovers a different address" do
    vectors["signatures"]["wrong_hash"].each do |row|
      assert_not_equal row["must_not_recover"], Chain::Signature.recover_hash(row["hash"], row["signature"]), row["name"]
    end
  end

  test "signer ordering is numeric" do
    order = vectors["signatures"]["order"]
    assert_equal order["sorted_ascending"], Chain::Address.sort(order["signers"])
  end

  test "prev owner comes from the live list" do
    vectors["prev_owner"].each do |row|
      assert_equal row["prev_owner"], Chain::ProposalBuilder.prev_owner(row["owners"], row["owner"])
    end
  end

  test "EIP-55 checksums" do
    vectors["checksums"].each do |row|
      assert_equal row["checksummed"], Chain::Address.checksum(row["lower"])
      assert_equal row["lower"], Chain::Address.normalize(row["checksummed"])
    end
  end
end
