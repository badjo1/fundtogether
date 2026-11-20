require "ecdsa"

module ChainTestHelper
  # Publicly known private keys, for tests only. Never fund them.
  KEYS = {
    alice: 1, bob: 2, carol: 3, dave: 4, erin: 5, frank: 6
  }.freeze
  SEPOLIA = 11_155_111
  GROUP = ECDSA::Group::Secp256k1

  def vectors
    @@vectors ||= JSON.parse(Rails.root.join("test/fixtures/safe_vectors.json").read)
  end

  def address_of(name)
    point = GROUP.generator.multiply_by_scalar(KEYS.fetch(name))
    Chain::Address.from_public_key(point.x, point.y)
  end

  # Deterministic low-s signing, so tests need no randomness.
  def sign_digest(name, digest)
    key = KEYS.fetch(name)
    order = GROUP.order
    k = (Chain::Hex.keccak([ key.to_s(16).rjust(64, "0") ].pack("H*") + digest).unpack1("H*").to_i(16) % (order - 1)) + 1
    point = GROUP.generator.multiply_by_scalar(k)
    r = point.x % order
    s = (k.pow(order - 2, order) * ((digest.unpack1("H*").to_i(16) + (r * key)) % order)) % order
    recovery = point.y.odd? ? 1 : 0
    if s > order / 2
      s = order - s
      recovery ^= 1
    end
    format("0x%064x%064x%02x", r, s, 27 + recovery)
  end

  def sign_hash(name, hash_hex)
    sign_digest(name, Chain::Hex.to_bin(hash_hex))
  end

  def sign_personal(name, message)
    sign_digest(name, Chain::Signature.personal_digest(message))
  end

  def high_s_copy(signature)
    order = GROUP.order
    r = signature[2, 64]
    s = signature[66, 64].to_i(16)
    v = signature[130, 2].to_i(16)
    format("0x%s%064x%02x", r, order - s, v == 27 ? 28 : 27)
  end

  def word(address)
    address.delete_prefix("0x").rjust(64, "0")
  end

  def install_fake_rpc(fake)
    Chain::Rpc.factory = ->(_chain) { fake }
    fake
  end

  def uninstall_fake_rpc
    Chain::Rpc.reset_factory!
  end

  def link_wallet(user, name_or_address)
    address = name_or_address.is_a?(Symbol) ? address_of(name_or_address) : name_or_address
    user.wallets.create!(address: address, verified_at: 1.day.ago)
  end

  # A fund with a verified Safe, set up directly: tests of later steps start here.
  def activate_safe(account, owners:, threshold:, safe: "0x1111111111111111111111111111111111111111", synced_block: 1000)
    chain = Chain::Registry.fetch(SEPOLIA)
    account.update!(chain_id: SEPOLIA, token_address: chain.token.address, safe_address: safe,
                    safe_salt_nonce: 1, safe_status: "active", safe_owners: owners, safe_threshold: threshold,
                    safe_verified_at: Time.current, synced_block: synced_block)
    account
  end

  def json
    JSON.parse(response.body)
  end
end

# A scripted chain. Implements the same read methods as Chain::Rpc. The state is plain data, so
# a test changes "the chain" by changing a field, and failure is switched on per method.
class FakeRpc
  Error = Chain::Rpc::Error

  attr_accessor :owners, :threshold, :nonce, :head, :finalized, :code, :singleton_address, :modules_list,
                :guard_address, :fallback_address, :balance, :native_balance, :transactions, :receipts, :blocks, :logs, :codes, :log_limit, :receipt_requests
  attr_reader :calls

  def initialize(chain: Chain::Registry.fetch(ChainTestHelper::SEPOLIA))
    @chain = chain
    @owners = []
    @threshold = 1
    @nonce = 0
    @head = 2000
    @finalized = 1900
    @code = "0x60"
    @codes = {}
    @singleton_address = chain.singleton
    @modules_list = []
    @guard_address = Chain::Address::ZERO
    @fallback_address = chain.fallback_handler
    @balance = 0
    @native_balance = 0
    @transactions = {}
    @receipts = {}
    @blocks = {}
    @logs = []
    @failing = {}
    @calls = []
    @receipt_requests = []
  end

  attr_reader :chain

  def fail_with(method, error = Chain::Rpc::Unavailable.new("kapot"))
    @failing[method] = error
  end

  def heal!
    @failing.clear
  end

  def maybe_fail(method)
    @calls << method
    raise @failing[method] if @failing[method]
    raise @failing[:all] if @failing[:all]
  end

  def block_number
    maybe_fail(:block_number)
    head
  end

  def eth_call(to:, data:)
    maybe_fail(:eth_call)
    selector = data[0, 10]
    case selector
    when sel(:get_owners) then enc(%w[address[]], [ owners ])
    when sel(:get_threshold) then enc(%w[uint256], [ threshold ])
    when sel(:nonce) then enc(%w[uint256], [ nonce ])
    when sel(:balance_of) then enc(%w[uint256], [ balance ])
    when sel(:get_modules_paginated) then enc(%w[address[] address], [ modules_list, Chain::Address::SENTINEL ])
    else "0x"
    end
  end

  def get_balance(_address)
    maybe_fail(:get_balance)
    native_balance
  end

  def get_transaction(tx_hash)
    maybe_fail(:get_transaction)
    transactions[tx_hash]
  end

  # One request on the wire, however many blocks.
  def get_blocks(numbers)
    maybe_fail(:get_blocks)
    numbers.to_h { |number| [ number, blocks.fetch(number) { { number: number, hash: self.class.block_hash(number), timestamp: 1_700_000_000 + number } } ] }
  end

  def get_code(address)
    maybe_fail(:get_code)
    codes.fetch(address) { code }
  end

  def get_storage_at(_address, slot)
    maybe_fail(:get_storage_at)
    address = case slot
    when "0x0" then singleton_address
    when Chain::SafeReader::GUARD_SLOT then guard_address
    when Chain::SafeReader::FALLBACK_SLOT then fallback_address
    end
    "0x#{address.delete_prefix('0x').rjust(64, '0')}"
  end

  def get_logs(address:, topics:, from_block:, to_block:)
    maybe_fail(:get_logs)
    raise Chain::Rpc::RangeTooLarge, "te groot" if log_limit && (to_block - from_block + 1) > log_limit

    logs.select do |log|
      log[:address] == address && log[:block_number].between?(from_block, to_block) &&
        topics.each_with_index.all? do |filter, index|
          filter.nil? || Array(filter).include?(log[:topics][index])
        end
    end
  end

  def get_block(number_or_tag)
    maybe_fail(:get_block)
    number = case number_or_tag
    when "finalized" then finalized
    when "latest" then head
    else number_or_tag
    end
    return nil if number.nil?

    blocks.fetch(number) { { number: number, hash: self.class.block_hash(number), timestamp: 1_700_000_000 + number } }
  end

  def get_receipt(tx_hash)
    maybe_fail(:get_receipt)
    @receipt_requests << tx_hash
    receipts[tx_hash]
  end

  def self.block_hash(number)
    format("0x%064x", number + 0xabc000)
  end

  private

  def sel(name)
    Chain::Abi.selector_hex(Chain::Abi::SELECTORS.fetch(name))
  end

  def enc(types, values)
    Chain::Hex.from_bin(Chain::Abi.encode(types, values))
  end
end

ActiveSupport.on_load(:active_support_test_case) { include ChainTestHelper }
ActiveSupport.on_load(:action_dispatch_integration_test) { include ChainTestHelper }
