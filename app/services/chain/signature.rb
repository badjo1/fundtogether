require "ecdsa"

module Chain
  # Local secp256k1 recovery. Identity is never delegated to an RPC.
  #
  # Accepted: exactly 65 bytes, r and s in range, low-s only (EIP-2). Every mainstream
  # wallet emits low-s, and the Safe does not enforce it, so a high-s signature is a
  # malleated copy and is rejected rather than normalised. v 27/28 is canonical. v 0/1
  # (some hardware wallet paths) is normalised to 27/28, because the Safe contract would
  # read a raw 0/1 as a contract signature or pre-approved hash. Anything else is refused,
  # including v 31/32: FundTogether never signs a Safe hash with eth_sign.
  module Signature
    class Invalid < StandardError; end

    GROUP = ECDSA::Group::Secp256k1
    ORDER = GROUP.order
    HALF_ORDER = ORDER / 2
    FORMAT = /\A0x[0-9a-fA-F]{130}\z/

    Parsed = Data.define(:r, :s, :v) do
      def to_hex
        format("0x%064x%064x%02x", r, s, v)
      end
    end

    module_function

    def parse(signature)
      raise Invalid, "malformed" unless signature.is_a?(String) && FORMAT.match?(signature)

      body = signature.delete_prefix("0x")
      r = body[0, 64].to_i(16)
      s = body[64, 64].to_i(16)
      v = body[128, 2].to_i(16)
      v += 27 if v < 2
      raise Invalid, "bad_v" unless [ 27, 28 ].include?(v)
      raise Invalid, "bad_r" unless r.between?(1, ORDER - 1)
      raise Invalid, "bad_s" unless s.between?(1, ORDER - 1)
      raise Invalid, "high_s" if s > HALF_ORDER

      Parsed.new(r: r, s: s, v: v)
    end

    # The canonical form we store: lowercase, v 27/28.
    def normalize(signature)
      parse(signature).to_hex
    end

    # digest is a 32-byte binary string. Returns the lowercase signer address.
    def recover_digest(digest, signature)
      raise Invalid, "bad_digest" unless digest.is_a?(String) && digest.bytesize == 32

      parsed = parse(signature)
      recover_point(digest, parsed)
    end

    def recover_hash(hash_hex, signature)
      recover_digest(Hex.to_bin(hash_hex), signature)
    rescue Hex::InvalidHex
      raise Invalid, "bad_digest"
    end

    # EIP-191 personal_sign over raw message bytes.
    def personal_digest(message)
      binary = message.b
      Hex.keccak("\x19Ethereum Signed Message:\n#{binary.bytesize}".b + binary)
    end

    def recover_personal(message, signature)
      recover_digest(personal_digest(message), signature)
    end

    def recover_point(digest, parsed)
      field = GROUP.field
      y_squared = field.mod(parsed.r.pow(3, field.prime) + GROUP.param_b)
      roots = field.square_roots(y_squared)
      raise Invalid, "bad_r" if roots.empty?

      y = roots.find { |root| root.odd? == parsed.v.even? } || raise(Invalid, "bad_r")
      point = GROUP.new_point([ parsed.r, y ])
      z = digest.unpack1("H*").to_i(16) % ORDER
      r_inverse = parsed.r.pow(ORDER - 2, ORDER)
      s_part = (parsed.s * r_inverse) % ORDER
      z_part = (ORDER - ((z * r_inverse) % ORDER)) % ORDER
      public_key = point.multiply_by_scalar(s_part).add_to_point(GROUP.generator.multiply_by_scalar(z_part))
      raise Invalid, "no_public_key" if public_key.infinity?

      Address.from_public_key(public_key.x, public_key.y)
    end
    private_class_method :recover_point
  end
end
