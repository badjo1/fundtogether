module Chain
  # Safe initializer and CREATE2 address derivation (docs/research/safe-integration.md section 4).
  module Create2
    # SafeProxyFactory 1.4.1 proxyCreationCode(). Identical on Gnosis, Sepolia and Base;
    # the shared vectors and the live test assert its keccak.
    PROXY_CREATION_CODE = "0x" \
      "608060405234801561001057600080fd5b506040516101e63803806101e68339818101604052602081101561003357600080" \
      "fd5b8101908080519060200190929190505050600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffff" \
      "ffffffffffffffffffffffffffffff1614156100ca576040517f08c379a00000000000000000000000000000000000000000" \
      "000000000000000081526004018080602001828103825260228152602001806101c460229139604001915050604051809103" \
      "90fd5b806000806101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffff" \
      "ffffffffffffffffffffff1602179055505060ab806101196000396000f3fe608060405273ffffffffffffffffffffffffff" \
      "ffffffffffffff600054167fa619486e00000000000000000000000000000000000000000000000000000000600035141560" \
      "50578060005260206000f35b3660008037600080366000845af43d6000803e60008114156070573d6000fd5b3d6000f3fea2" \
      "64697066735822122003d1488ee65e08fa41e58e888a9865554c535f2c77126a82cb4c0f917f31441364736f6c6343000706" \
      "0033496e76616c69642073696e676c65746f6e20616464726573732070726f7669646564".freeze
    PROXY_CREATION_CODE_KECCAK = "0x1856e0ee08399d74e0ea0b03adca210aeade6f748969ac023cdcb4dd62dcaf5f".freeze
    SALT_PREFIX = "fundtogether.safe.v1".freeze

    module_function

    # setup(owners, threshold, 0, 0x, fallbackHandler, 0, 0, 0). No delegatecall during
    # setup and no payment: both are always the zero value here.
    def initializer(owners:, threshold:, fallback_handler:)
      Abi.call(
        :setup,
        %w[address[] uint256 address bytes address address uint256 address],
        [ owners, threshold, Address::ZERO, "0x", fallback_handler, Address::ZERO, 0, Address::ZERO ]
      )
    end

    # uint256(keccak256("fundtogether.safe.v1" ++ uuid ++ uint256(chain_id) ++ uint256(attempt)))
    def salt_nonce(group_uuid:, chain_id:, attempt: 0)
      preimage = SALT_PREFIX.b + group_uuid.to_s.b + Abi.encode_uint(chain_id) + Abi.encode_uint(attempt)
      Hex.keccak(preimage).unpack1("H*").to_i(16)
    end

    def salt(initializer:, salt_nonce:)
      Hex.keccak(Hex.keccak(Hex.to_bin(initializer)) + Abi.encode_uint(salt_nonce))
    end

    # The transaction that deploys this fund's Safe, and nothing else.
    def calldata(account)
      chain = account.chain
      init = initializer(owners: account.safe_owners, threshold: account.safe_threshold, fallback_handler: chain.fallback_handler)
      Abi.call(:create_proxy_with_nonce, %w[address bytes uint256], [ chain.singleton, init, account.safe_salt_nonce.to_i ])
    end

    def predict(factory:, singleton:, initializer:, salt_nonce:)
      init_code = Hex.to_bin(PROXY_CREATION_CODE) + Abi.encode_address(singleton)
      preimage = "\xff".b + Hex.to_bin(Address.normalize(factory)) +
                 salt(initializer: initializer, salt_nonce: salt_nonce) + Hex.keccak(init_code)
      Hex.from_bin(Hex.keccak(preimage).byteslice(12, 20))
    end
  end
end
