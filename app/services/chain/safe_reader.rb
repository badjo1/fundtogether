module Chain
  # Live reads of a Safe. Advisory by nature (it trusts the RPC) and never cached.
  # Empty or malformed return data raises, so a missing contract cannot look like zero.
  class SafeReader
    GUARD_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8".freeze
    FALLBACK_SLOT = "0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5".freeze
    MODULE_PAGE = 10

    Snapshot = Data.define(:owners, :threshold, :nonce) do
      def owner?(address)
        owners.include?(address)
      end
    end

    def initialize(chain:, safe:, rpc: Rpc.for(chain))
      @chain = chain
      @safe = safe
      @rpc = rpc
    end

    def self.for_account(account, rpc: nil)
      chain = account.chain
      new(chain: chain, safe: account.safe_address, rpc: rpc || Rpc.for(chain))
    end

    def snapshot
      Snapshot.new(owners: owners, threshold: threshold, nonce: nonce)
    end

    def owners
      list = decode("address[]", :get_owners)
      raise Rpc::InvalidResponse, "getOwners leeg" if list.empty?

      list
    end

    def threshold
      value = decode("uint256", :get_threshold)
      raise Rpc::InvalidResponse, "getThreshold nul" if value.zero?

      value
    end

    def nonce
      decode("uint256", :nonce)
    end

    def code
      @rpc.get_code(@safe)
    end

    def singleton
      slot_address("0x0")
    end

    def guard
      slot_address(GUARD_SLOT)
    end

    def fallback_handler
      slot_address(FALLBACK_SLOT)
    end

    def modules
      data = Abi.call(:get_modules_paginated, %w[address uint256], [ Address::SENTINEL, MODULE_PAGE ])
      Abi.decode(%w[address[] address], @rpc.eth_call(to: @safe, data: data)).first
    rescue Abi::DecodeError => e
      raise Rpc::InvalidResponse, "getModulesPaginated: #{e.message}"
    end

    def token_balance(token_address)
      data = Abi.call(:balance_of, %w[address], [ @safe ])
      Abi.decode_one("uint256", @rpc.eth_call(to: token_address, data: data))
    rescue Abi::DecodeError => e
      raise Rpc::InvalidResponse, "balanceOf: #{e.message}"
    end

    def native_balance
      @rpc.get_balance(@safe)
    end

    private

    def decode(type, selector)
      Abi.decode_one(type, @rpc.eth_call(to: @safe, data: Abi.call(selector)))
    rescue Abi::DecodeError => e
      raise Rpc::InvalidResponse, "#{selector}: #{e.message}"
    end

    def slot_address(slot)
      word = @rpc.get_storage_at(@safe, slot)
      raise Rpc::InvalidResponse, "slot #{slot}" unless word.start_with?("0x000000000000000000000000")

      "0x#{word[-40..]}"
    end
  end
end
