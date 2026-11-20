require "digest/keccak"

module Chain
  # Hex and keccak helpers. Everything leaving this module is lowercase and 0x-prefixed.
  module Hex
    class InvalidHex < ArgumentError; end

    HEX = /\A0x(?:[0-9a-fA-F]{2})*\z/
    HASH = /\A0x[0-9a-f]{64}\z/

    module_function

    def bytes?(value)
      value.is_a?(String) && HEX.match?(value)
    end

    def to_bin(value)
      raise InvalidHex, "ongeldige hex" unless bytes?(value)

      [ value.delete_prefix("0x") ].pack("H*")
    end

    def from_bin(binary)
      "0x#{binary.unpack1('H*')}"
    end

    def keccak(binary)
      Digest::Keccak.new(256).digest(binary)
    end

    def keccak_hex(hex)
      from_bin(keccak(to_bin(hex)))
    end

    def hash?(value)
      value.is_a?(String) && HASH.match?(value)
    end

    # A JSON-RPC quantity (eth_blockNumber and friends). Leading zeros are tolerated because
    # some nodes send them; an empty value never is.
    def quantity(value)
      raise InvalidHex, "ongeldige quantity" unless value.is_a?(String) && value.match?(/\A0x[0-9a-fA-F]{1,64}\z/)

      value.delete_prefix("0x").to_i(16)
    end

    def from_uint(number)
      "0x#{number.to_s(16)}"
    end
  end
end
