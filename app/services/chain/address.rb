module Chain
  # Ethereum addresses. Stored and compared lowercase. Mixed-case input must carry a
  # correct EIP-55 checksum, because a typo in a mixed-case address is detectable.
  module Address
    class Invalid < ArgumentError; end

    FORMAT = /\A0x[0-9a-fA-F]{40}\z/
    LOWER = /\A0x[0-9a-f]{40}\z/
    ZERO = "0x0000000000000000000000000000000000000000".freeze
    SENTINEL = "0x0000000000000000000000000000000000000001".freeze

    module_function

    def normalize(value)
      raise Invalid, "ongeldig adres" unless value.is_a?(String) && FORMAT.match?(value)

      body = value.delete_prefix("0x")
      mixed = body != body.downcase && body != body.upcase
      raise Invalid, "ongeldige adres-checksum" if mixed && checksum(value) != value

      value.downcase
    end

    def checksum(value)
      body = value.delete_prefix("0x").downcase
      digest = Digest::Keccak.new(256).hexdigest(body)
      cased = body.each_char.with_index.map { |char, index| digest[index].to_i(16) >= 8 ? char.upcase : char }
      "0x#{cased.join}"
    end

    # Owner order on-chain is arbitrary; the Safe wants signatures ordered numerically.
    def sort(addresses)
      addresses.sort_by { |address| address.delete_prefix("0x").to_i(16) }
    end

    def from_public_key(point_x, point_y)
      binary = [ point_x.to_s(16).rjust(64, "0") + point_y.to_s(16).rjust(64, "0") ].pack("H*")
      "0x#{Digest::Keccak.new(256).hexdigest(binary)[-40..]}"
    end
  end
end
