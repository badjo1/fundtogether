require "test_helper"

class ChainRpcTest < ActiveSupport::TestCase
  # Scripted HTTP: answers per URL, as a queue of [status, body] or exceptions.
  class ScriptedTransport
    attr_reader :requests

    def initialize(&handler)
      @handler = handler
      @requests = []
    end

    def post(url, body)
      request = JSON.parse(body)
      @requests << [ url, request["method"], request["params"] ]
      @handler.call(url, request)
    end
  end

  CHAIN = Chain::Registry::Config.new(
    key: "testchain", chain_id: 11_155_111, name: "Test", testnet: true, native_symbol: "ETH", explorer_url: "https://x",
    confirmations: 10, rpc_urls: %w[https://one.example https://two.example], public_rpc_urls: [], singleton: "0x", factory: "0x",
    fallback_handler: "0x", token: nil
  )
  ALICE = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf".freeze

  setup { Chain::Rpc.verified_endpoints.clear }

  # Found live on Sepolia: a refused proxy CONNECT raised Net::HTTPFatalError past the transport, so the balance
  # frame answered 500 instead of the outage text. Anything HTTP can throw here has to count as an outage.
  def with_local_server(reply)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      socket = server.accept
      while (line = socket.gets) && line != "\r\n"; end
      socket.write(reply)
      socket.close
    end
    yield server.addr[1]
  ensure
    thread&.kill
    server&.close
  end

  test "a malformed HTTP answer from an endpoint is a transport error" do
    with_local_server("this is not http\r\n\r\n") do |port|
      assert_raises(Chain::Rpc::TransportError) { Chain::Rpc::NetHttpTransport.new.post("http://127.0.0.1:#{port}/", "{}") }
    end
  end

  test "a proxy refusing the connection is a transport error" do
    with_local_server("HTTP/1.1 503 Service Unavailable\r\n\r\n") do |port|
      previous = ENV["http_proxy"]
      ENV["http_proxy"] = "http://127.0.0.1:#{port}"
      begin
        assert_raises(Chain::Rpc::TransportError) { Chain::Rpc::NetHttpTransport.new.post("https://rpc.example/", "{}") }
      ensure
        ENV["http_proxy"] = previous
      end
    end
  end

  def ok(request, result)
    [ 200, { jsonrpc: "2.0", id: request["id"], result: result }.to_json ]
  end

  def rpc_error(request, code, message)
    [ 200, { jsonrpc: "2.0", id: request["id"], error: { code: code, message: message } }.to_json ]
  end

  def client(&handler)
    transport = ScriptedTransport.new do |url, request|
      if request["method"] == "eth_chainId"
        ok(request, "0xaa36a7")
      else
        handler.call(url, request)
      end
    end
    [ Chain::Rpc.new(CHAIN, transport: transport), transport ]
  end

  def per_endpoint(first, second = nil)
    lambda do |url, request|
      url == "https://one.example" ? first.call(request) : second.call(request)
    end
  end

  test "uses the first endpoint when it answers" do
    rpc, transport = client { |_, request| ok(request, "0x10") }
    assert_equal 16, rpc.block_number
    assert_equal [ "https://one.example" ], transport.requests.reject { |r| r[1] == "eth_chainId" }.map(&:first)
  end

  { "429" => [ 429, "busy" ], "500" => [ 500, "oops" ], "503" => [ 503, "" ], "403" => [ 403, "no" ], "redirect" => [ 302, "" ] }.each do |name, answer|
    test "falls back on HTTP #{name}" do
      rpc, = client(&per_endpoint(->(_) { answer }, ->(request) { ok(request, "0x10") }))
      assert_equal 16, rpc.block_number
    end
  end

  test "falls back on a timeout" do
    rpc, = client(&per_endpoint(->(_) { raise Chain::Rpc::TransportError, "Net::ReadTimeout" }, ->(request) { ok(request, "0x10") }))
    assert_equal 16, rpc.block_number
  end

  [ "not json", "[]", "{}", '{"jsonrpc":"2.0"}', '{"jsonrpc":"1.0","id":1,"result":"0x1"}' ].each do |body|
    test "falls back on the malformed answer #{body}" do
      rpc, = client(&per_endpoint(->(_) { [ 200, body ] }, ->(request) { ok(request, "0x10") }))
      assert_equal 16, rpc.block_number
    end
  end

  test "an answer with another request id is not accepted" do
    rpc, = client(&per_endpoint(->(request) { [ 200, { jsonrpc: "2.0", id: request["id"] + 1, result: "0x1" }.to_json ] }, ->(request) { ok(request, "0x10") }))
    assert_equal 16, rpc.block_number
  end

  test "all endpoints failing raises instead of returning a default" do
    rpc, = client { [ 500, "" ] }
    assert_raises(Chain::Rpc::Unavailable) { rpc.block_number }
    assert_raises(Chain::Rpc::Unavailable) { rpc.get_code(ALICE) }
    assert_raises(Chain::Rpc::Unavailable) { rpc.get_logs(address: ALICE, topics: [], from_block: 1, to_block: 2) }
  end

  test "a result of the wrong shape raises" do
    [ nil, 16, "16", "", "0x", {}, [] ].each do |bad|
      rpc, = client { |_, request| ok(request, bad) }
      assert_raises(Chain::Rpc::Error, bad.inspect) { rpc.block_number }
    end
    rpc, = client { |_, request| ok(request, "zz") }
    assert_raises(Chain::Rpc::Error) { rpc.get_code(ALICE) }
    assert_raises(Chain::Rpc::Error) { rpc.eth_call(to: ALICE, data: "0x") }
  end

  test "range errors fall back, and raise RangeTooLarge when every endpoint refuses" do
    rpc, = client { |_, request| rpc_error(request, -32_602, "eth_getLogs is limited to 0 - 50 blocks range") }
    assert_raises(Chain::Rpc::RangeTooLarge) { rpc.get_logs(address: ALICE, topics: [], from_block: 1, to_block: 2000) }

    rpc, = client(&per_endpoint(
      ->(request) { rpc_error(request, -32_005, "query returned more than 10000 results") },
      ->(request) { ok(request, []) }
    ))
    assert_equal [], rpc.get_logs(address: ALICE, topics: [], from_block: 1, to_block: 2000)
  end

  test "a rate limit message on getLogs is not mistaken for a range problem" do
    rpc, = client { |_, request| rpc_error(request, -32_005, "rate limit exceeded") }
    assert_raises(Chain::Rpc::Unavailable) { rpc.get_logs(address: ALICE, topics: [], from_block: 1, to_block: 2) }
  end

  test "a revert is an answer: no fallback" do
    rpc, transport = client { |_, request| rpc_error(request, 3, "execution reverted: GS013") }
    assert_raises(Chain::Rpc::Reverted) { rpc.eth_call(to: ALICE, data: "0x") }
    assert_equal 1, transport.requests.count { |r| r[1] == "eth_call" }
  end

  test "an endpoint on the wrong chain is skipped" do
    transport = ScriptedTransport.new do |url, request|
      if request["method"] == "eth_chainId"
        ok(request, url == "https://one.example" ? "0x1" : "0xaa36a7")
      else
        ok(request, url == "https://one.example" ? "0xdead" : "0x10")
      end
    end
    assert_equal 16, Chain::Rpc.new(CHAIN, transport: transport).block_number
    assert_empty transport.requests.select { |r| r[0] == "https://one.example" && r[1] != "eth_chainId" }
  end

  test "only allowlisted read methods exist" do
    rpc, transport = client { |_, request| ok(request, "0x1") }
    %w[eth_sendRawTransaction eth_sendTransaction eth_sign personal_sign debug_traceTransaction].each do |method|
      assert_raises(ArgumentError) { rpc.call(method) }
    end
    assert_empty transport.requests
  end

  test "addresses are validated before they reach a request" do
    rpc, transport = client { |_, request| ok(request, "0x") }
    assert_raises(Chain::Address::Invalid) { rpc.get_code("https://evil.example") }
    assert_raises(Chain::Address::Invalid) { rpc.eth_call(to: "0x12", data: "0x") }
    assert_empty transport.requests
  end

  test "normalises logs and refuses malformed ones" do
    log = { "address" => ALICE.upcase.sub("0X", "0x"), "topics" => [ "0x#{'A' * 64}" ], "data" => "0x", "blockNumber" => "0x10",
            "blockHash" => "0x#{'b' * 64}", "transactionHash" => "0x#{'c' * 64}", "logIndex" => "0x1" }
    rpc, = client { |_, request| ok(request, [ log ]) }
    parsed = rpc.get_logs(address: ALICE, topics: [], from_block: 1, to_block: 2).first
    assert_equal ALICE, parsed[:address]
    assert_equal "0x#{'a' * 64}", parsed[:topics].first
    assert_equal 16, parsed[:block_number]

    log.except("logIndex").then do |broken|
      rpc, = client { |_, request| ok(request, [ broken ]) }
      assert_raises(Chain::Rpc::InvalidResponse) { rpc.get_logs(address: ALICE, topics: [], from_block: 1, to_block: 2) }
    end
    rpc, = client { |_, request| ok(request, [ "nonsense" ]) }
    assert_raises(Chain::Rpc::InvalidResponse) { rpc.get_logs(address: ALICE, topics: [], from_block: 1, to_block: 2) }
  end

  test "a missing block or receipt is nil, a malformed one raises" do
    rpc, = client { |_, request| ok(request, nil) }
    assert_nil rpc.get_block(5)
    assert_nil rpc.get_receipt("0x#{'a' * 64}")
    rpc, = client { |_, request| ok(request, { "number" => "0x1" }) }
    assert_raises(Chain::Rpc::InvalidResponse) { rpc.get_block(5) }
    assert_raises(Chain::Rpc::InvalidResponse) { rpc.get_receipt("0x#{'a' * 64}") }
    assert_raises(ArgumentError) { rpc.get_receipt("0x12") }
  end

  test "the safe reader refuses empty answers from a non-contract" do
    rpc, = client { |_, request| ok(request, "0x") }
    reader = Chain::SafeReader.new(chain: CHAIN, safe: ALICE, rpc: rpc)
    assert_raises(Chain::Rpc::InvalidResponse) { reader.owners }
    assert_raises(Chain::Rpc::InvalidResponse) { reader.threshold }
    assert_raises(Chain::Rpc::InvalidResponse) { reader.nonce }
    assert_raises(Chain::Rpc::InvalidResponse) { reader.token_balance(ALICE) }
    assert_raises(Chain::Rpc::InvalidResponse) { reader.modules }
  end
end
