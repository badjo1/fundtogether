require "test_helper"

# Optional: LIVE_RPC=1 bin/rails test test/services/chain/live_rpc_test.rb
# Read-only against public Sepolia endpoints. Sends nothing. Skipped in CI.
class ChainLiveRpcTest < ActiveSupport::TestCase
  SAFE_ON_SEPOLIA = "0x9cd26fca10660d4e2b207be5693a605150eb6243".freeze

  setup { skip "LIVE_RPC=1 om tegen Sepolia te testen" unless ENV["LIVE_RPC"] == "1" }

  def chain
    Chain::Registry.fetch(11_155_111)
  end

  test "the real factory, singleton, token and a real Safe read as expected" do
    rpc = Chain::Rpc.new(chain)
    assert_equal "0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317", Chain::Hex.keccak_hex(rpc.get_code(chain.factory))
    assert_equal "0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff", Chain::Hex.keccak_hex(rpc.get_code(chain.singleton))
    assert_equal "1.4.1", Chain::Abi.decode_one("string", rpc.eth_call(to: chain.singleton, data: Chain::Abi.call(:version)))
    code = Chain::Abi.decode_one("bytes", rpc.eth_call(to: chain.factory, data: Chain::Abi.call(:proxy_creation_code)))
    assert_equal Chain::Create2::PROXY_CREATION_CODE, code

    assert_operator rpc.block_number, :>, 1_000_000
    assert_operator rpc.get_block("finalized")[:number], :>, 1_000_000

    reader = Chain::SafeReader.new(chain: chain, safe: SAFE_ON_SEPOLIA, rpc: rpc)
    assert_equal chain.singleton, reader.singleton
    assert_operator reader.owners.length, :>=, 1
    assert_operator reader.threshold, :>=, 1
    assert_kind_of Integer, reader.token_balance(chain.token.address)
  end

  test "a real deployment receipt shows the predicted address" do
    row = vectors["create2"].find { |vector| vector["chain_id"] == 11_155_111 && vector["tx_hash"] }
    receipt = Chain::Rpc.new(chain).get_receipt(row["tx_hash"])
    assert_equal 1, receipt[:status]
    creation = receipt[:logs].find { |log| log[:topics][0] == vectors["constants"]["topics"]["ProxyCreation"]["topic"] }
    assert_equal row["predicted_address"], "0x#{creation[:topics][1][-40..]}"
  end

  test "real token logs parse, and an empty answer from a non-contract raises" do
    rpc = Chain::Rpc.new(chain)
    head = rpc.block_number
    logs = rpc.get_logs(address: chain.token.address, topics: [ Chain::LogSync::TRANSFER ], from_block: head - 200, to_block: head - 100)
    assert_kind_of Array, logs
    reader = Chain::SafeReader.new(chain: chain, safe: "0x000000000000000000000000000000000000dead", rpc: rpc)
    assert_raises(Chain::Rpc::InvalidResponse) { reader.threshold }
  end
end
