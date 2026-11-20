module Chain
  # SafeTx EIP-712 hashing, local only. The domain has no name or version on Safe 1.4.1.
  module Eip712
    DOMAIN_TYPE = "EIP712Domain(uint256 chainId,address verifyingContract)".freeze
    SAFE_TX_TYPE = "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas," \
                   "uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)".freeze
    DOMAIN_TYPEHASH = Hex.from_bin(Hex.keccak(DOMAIN_TYPE)).freeze
    SAFE_TX_TYPEHASH = Hex.from_bin(Hex.keccak(SAFE_TX_TYPE)).freeze

    module_function

    def domain_separator(chain_id:, safe:)
      Hex.from_bin(Hex.keccak(Abi.encode(%w[bytes32 uint256 address], [ DOMAIN_TYPEHASH, chain_id, safe ])))
    end

    def struct_hash(to:, value:, data:, operation:, nonce:, safe_tx_gas: 0, base_gas: 0, gas_price: 0,
                    gas_token: Address::ZERO, refund_receiver: Address::ZERO)
      encoded = Abi.encode(
        %w[bytes32 address uint256 bytes32 uint8 uint256 uint256 uint256 address address uint256],
        [ SAFE_TX_TYPEHASH, to, value, Hex.keccak_hex(data), operation,
          safe_tx_gas, base_gas, gas_price, gas_token, refund_receiver, nonce ]
      )
      Hex.from_bin(Hex.keccak(encoded))
    end

    def safe_tx_hash(chain_id:, safe:, **fields)
      preimage = "\x19\x01".b + Hex.to_bin(domain_separator(chain_id: chain_id, safe: safe)) +
                 Hex.to_bin(struct_hash(**fields))
      Hex.from_bin(Hex.keccak(preimage))
    end
  end
end
