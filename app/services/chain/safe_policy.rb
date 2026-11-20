module Chain
  # What a FundTogether Safe proposal may contain. Mirrors app/javascript/safe; both are held
  # to test/fixtures/safe_vectors.json. Checks run in a fixed order and the first failure wins.
  module SafePolicy
    TRANSFER = Abi.selector_hex(Abi::SELECTORS[:transfer])
    ADD_OWNER = Abi.selector_hex(Abi::SELECTORS[:add_owner_with_threshold])
    REMOVE_OWNER = Abi.selector_hex(Abi::SELECTORS[:remove_owner])
    SWAP_OWNER = Abi.selector_hex(Abi::SELECTORS[:swap_owner])
    CHANGE_THRESHOLD = Abi.selector_hex(Abi::SELECTORS[:change_threshold])
    # Allowed self-calls: argument layout per selector.
    OWNER_CALLS = {
      ADD_OWNER => %i[new_owner threshold],
      REMOVE_OWNER => %i[prev_owner owner threshold],
      SWAP_OWNER => %i[prev_owner owner new_owner],
      CHANGE_THRESHOLD => %i[threshold]
    }.freeze

    module_function

    # tx: to, value, data, operation, nonce and optionally the gas fields, as decimal strings
    # or integers. Returns the refusal code, or nil when allowed.
    def violation(tx, safe:, token:, current_nonce:)
      fixed_field_violation(tx) || nonce_violation(tx, current_nonce) || target_violation(tx, safe, token)
    end

    def check!(tx, safe:, token:, current_nonce:)
      code = violation(tx, safe: safe, token: token, current_nonce: current_nonce)
      raise Refusal.new(code) if code
    end

    def fixed_field_violation(tx)
      return "operation_not_call" unless tx[:operation].to_i.zero? && tx[:operation].to_s == "0"
      return "safe_tx_gas_nonzero" unless zero?(tx[:safe_tx_gas])
      return "base_gas_nonzero" unless zero?(tx[:base_gas])
      return "gas_price_nonzero" unless zero?(tx[:gas_price])
      return "gas_token_nonzero" unless zero_address?(tx[:gas_token])
      "refund_receiver_nonzero" unless zero_address?(tx[:refund_receiver])
    end

    def nonce_violation(tx, current_nonce)
      "nonce_too_low" if integer(tx[:nonce]).nil? || integer(tx[:nonce]) < integer(current_nonce)
    end

    def target_violation(tx, safe, token)
      to = tx[:to]
      return "to_forbidden" unless to.is_a?(String) && to.match?(Address::LOWER)
      return "to_forbidden" if [ Address::ZERO, Address::SENTINEL ].include?(to)

      value = integer(tx[:value])
      return "malformed_calldata" if value.nil? || value.negative?
      return "malformed_calldata" unless tx[:data].is_a?(String) && tx[:data].match?(/\A0x(?:[0-9a-f]{2})*\z/)

      if to == safe then self_call_violation(tx[:data], value)
      elsif to == token then token_call_violation(tx[:data], value)
      elsif tx[:data] != "0x" then "unknown_target_data"
      elsif value.zero? then "empty_call"
      end
    end

    def self_call_violation(data, value)
      return "self_call_value" if value.positive?
      return nil if data == "0x"

      layout = OWNER_CALLS[data[0, 10]]
      return "self_call_forbidden" unless layout

      owner_call_arguments_violation(data, layout)
    end

    def owner_call_arguments_violation(data, layout)
      words = words_of(data, layout.length)
      return "malformed_calldata" unless words

      layout.zip(words).each do |role, word|
        case role
        when :threshold
          return "malformed_calldata" if word.to_i(16).zero?
        when :new_owner
          return "malformed_calldata" unless clean_address?(word) && !special_address?(word)
        when :owner
          return "malformed_calldata" unless clean_address?(word) && !special_address?(word)
        when :prev_owner
          return "malformed_calldata" unless clean_address?(word) && word.to_i(16) != 0
        end
      end
      nil
    end

    def token_call_violation(data, value)
      return "token_call_forbidden" unless data[0, 10] == TRANSFER
      return "token_call_value" if value.positive?

      words = words_of(data, 2)
      return "malformed_calldata" unless words && clean_address?(words[0]) && words[0].to_i(16) != 0
      return "malformed_calldata" if words[1].to_i(16).zero?

      nil
    end

    # The argument words of a selector call, or nil unless the length is exact.
    def words_of(data, count)
      body = data[10..].to_s
      return nil unless body.length == count * 64

      body.scan(/.{64}/)
    end

    def clean_address?(word)
      word.start_with?("0" * 24)
    end

    def special_address?(word)
      [ 0, 1 ].include?(word.to_i(16))
    end

    def zero?(value)
      value.nil? || integer(value)&.zero?
    end

    def zero_address?(value)
      value.nil? || value == Address::ZERO
    end

    def integer(value)
      return value if value.is_a?(Integer)

      value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)
    end
  end
end
