module Chain
  # Minimal ABI codec for the shapes FundTogether uses. Deliberately not general.
  # Types: address, uint256, uint8, bool, bytes32, bytes, string, address[].
  module Abi
    class EncodeError < ArgumentError; end
    class DecodeError < StandardError; end

    WORD = 32
    UINT256_MAX = (2**256) - 1
    DYNAMIC = %w[bytes string address[]].freeze

    SELECTORS = {
      transfer: "transfer(address,uint256)",
      balance_of: "balanceOf(address)",
      get_owners: "getOwners()",
      get_threshold: "getThreshold()",
      nonce: "nonce()",
      master_copy: "masterCopy()",
      get_modules_paginated: "getModulesPaginated(address,uint256)",
      setup: "setup(address[],uint256,address,bytes,address,address,uint256,address)",
      create_proxy_with_nonce: "createProxyWithNonce(address,bytes,uint256)",
      proxy_creation_code: "proxyCreationCode()",
      add_owner_with_threshold: "addOwnerWithThreshold(address,uint256)",
      remove_owner: "removeOwner(address,address,uint256)",
      swap_owner: "swapOwner(address,address,address)",
      change_threshold: "changeThreshold(uint256)",
      version: "VERSION()",
      domain_separator: "domainSeparator()"
    }.freeze

    module_function

    def selector(signature)
      Hex.keccak(signature)[0, 4]
    end

    def selector_hex(signature)
      Hex.from_bin(selector(signature))
    end

    # Calldata for a known function, as lowercase hex.
    def call(name, types = [], values = [])
      signature = SELECTORS.fetch(name)
      Hex.from_bin(selector(signature) + encode(types, values))
    end

    def encode(types, values)
      raise EncodeError, "aantal types en waarden verschilt" unless types.length == values.length

      head_size = types.length * WORD
      heads = +"".b
      tails = +"".b
      types.zip(values) do |type, value|
        if DYNAMIC.include?(type)
          heads << encode_uint(head_size + tails.bytesize)
          tails << encode_dynamic(type, value)
        else
          heads << encode_static(type, value)
        end
      end
      heads + tails
    end

    def encode_static(type, value)
      case type
      when "address" then encode_address(value)
      when "uint256" then encode_uint(value)
      when "uint8" then encode_uint(value, max: 255)
      when "bool" then encode_uint(value ? 1 : 0)
      when "bytes32" then encode_bytes32(value)
      else raise EncodeError, "type niet ondersteund: #{type}"
      end
    end

    def encode_dynamic(type, value)
      case type
      when "bytes" then encode_bytes(Hex.to_bin(value))
      when "string" then encode_bytes(value.to_s.b)
      when "address[]" then encode_uint(value.length) + value.map { |item| encode_address(item) }.join
      end
    end

    def encode_address(value)
      Hex.to_bin(Address.normalize(value)).rjust(WORD, "\x00".b)
    rescue Address::Invalid => e
      raise EncodeError, e.message
    end

    def encode_uint(value, max: UINT256_MAX)
      raise EncodeError, "waarde buiten bereik" unless value.is_a?(Integer) && value.between?(0, max)

      [ value.to_s(16).rjust(64, "0") ].pack("H*")
    end

    def encode_bytes32(value)
      raise EncodeError, "geen bytes32" unless Hex.bytes?(value) && value.length == 66

      Hex.to_bin(value)
    end

    def encode_bytes(binary)
      padding = (WORD - (binary.bytesize % WORD)) % WORD
      encode_uint(binary.bytesize) + binary + ("\x00".b * padding)
    end

    # Decodes hex return data. Refuses short data, out-of-bounds offsets and dirty address
    # padding, so an empty "0x" from a non-contract never turns into a silent zero.
    def decode(types, hex)
      binary = hex.is_a?(String) && Hex.bytes?(hex) ? Hex.to_bin(hex) : raise(DecodeError, "geen hex")
      raise DecodeError, "te weinig data" if binary.bytesize < types.length * WORD

      types.each_with_index.map do |type, index|
        word = read_word(binary, index * WORD)
        DYNAMIC.include?(type) ? decode_dynamic(type, binary, word_to_int(word)) : decode_static(type, word)
      end
    end

    def decode_one(type, hex)
      decode([ type ], hex).first
    end

    def decode_static(type, word)
      case type
      when "address" then decode_address(word)
      when "uint256" then word_to_int(word)
      when "uint8" then word_to_int(word).tap { |value| raise DecodeError, "uint8 buiten bereik" if value > 255 }
      when "bool"
        value = word_to_int(word)
        raise DecodeError, "geen bool" unless value <= 1

        value == 1
      when "bytes32" then Hex.from_bin(word)
      else raise DecodeError, "type niet ondersteund: #{type}"
      end
    end

    def decode_dynamic(type, binary, offset)
      length = word_to_int(read_word(binary, offset))
      raise DecodeError, "lengte buiten bereik" if length > binary.bytesize

      case type
      when "bytes", "string"
        raise DecodeError, "data te kort" if offset + WORD + length > binary.bytesize

        content = binary.byteslice(offset + WORD, length)
        type == "bytes" ? Hex.from_bin(content) : content.dup.force_encoding("UTF-8")
      when "address[]"
        Array.new(length) { |index| decode_address(read_word(binary, offset + WORD + (index * WORD))) }
      end
    end

    def decode_address(word)
      raise DecodeError, "vervuild adres" unless word.byteslice(0, 12) == ("\x00".b * 12)

      Hex.from_bin(word.byteslice(12, 20))
    end

    def read_word(binary, offset)
      raise DecodeError, "buiten bereik" if offset + WORD > binary.bytesize

      binary.byteslice(offset, WORD)
    end

    def word_to_int(word)
      word.unpack1("H*").to_i(16)
    end
  end
end
