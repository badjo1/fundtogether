module Chain
  # Turns typed parameters into to/value/data. Clients never submit calldata, and prev_owner
  # always comes from the live owner list. Pure: live state is passed in.
  module ProposalBuilder
    Built = Data.define(:kind, :params, :to, :value, :data, :operation)

    FIELDS = {
      "transfer_token" => %w[recipient amount],
      "transfer_native" => %w[recipient amount],
      "add_owner" => %w[owner threshold],
      "remove_owner" => %w[owner threshold],
      "swap_owner" => %w[old_owner new_owner],
      "change_threshold" => %w[threshold],
      "rejection" => %w[nonce]
    }.freeze

    module_function

    def build(kind:, params:, safe:, token:, owners:, threshold:, current_nonce:)
      fields = FIELDS[kind.to_s] || raise(Refusal.new("unknown_kind"))
      input = params.to_h.stringify_keys
      raise Refusal.new("unexpected_param") unless (input.keys - fields).empty?

      context = { safe: safe, token: token, owners: owners, threshold: threshold, current_nonce: current_nonce }
      send("build_#{kind}", input, context)
    end

    def build_transfer_token(input, context)
      recipient = recipient!(input["recipient"], context)
      amount = amount!(input["amount"])
      Built.new("transfer_token", { "recipient" => recipient, "amount" => amount.to_s }, context[:token], 0,
                Abi.call(:transfer, %w[address uint256], [ recipient, amount ]), 0)
    end

    def build_transfer_native(input, context)
      recipient = recipient!(input["recipient"], context)
      amount = amount!(input["amount"])
      Built.new("transfer_native", { "recipient" => recipient, "amount" => amount.to_s }, recipient, amount, "0x", 0)
    end

    def build_add_owner(input, context)
      owner = new_owner!(input["owner"], context)
      threshold = threshold!(input["threshold"], context[:owners].length + 1)
      owner_call("add_owner", { "owner" => owner, "threshold" => threshold }, context,
                 :add_owner_with_threshold, %w[address uint256], [ owner, threshold ])
    end

    def build_remove_owner(input, context)
      owner = existing_owner!(input["owner"], context)
      raise Refusal.new("last_owner") if context[:owners].length == 1

      threshold = threshold!(input["threshold"], context[:owners].length - 1)
      owner_call("remove_owner", { "owner" => owner, "threshold" => threshold }, context, :remove_owner,
                 %w[address address uint256], [ prev_owner(context[:owners], owner), owner, threshold ])
    end

    def build_swap_owner(input, context)
      old_owner = existing_owner!(input["old_owner"], context)
      new_owner = new_owner!(input["new_owner"], context)
      owner_call("swap_owner", { "old_owner" => old_owner, "new_owner" => new_owner }, context, :swap_owner,
                 %w[address address address], [ prev_owner(context[:owners], old_owner), old_owner, new_owner ])
    end

    def build_change_threshold(input, context)
      threshold = threshold!(input["threshold"], context[:owners].length)
      raise Refusal.new("threshold_unchanged") if threshold == context[:threshold]

      owner_call("change_threshold", { "threshold" => threshold }, context, :change_threshold, %w[uint256], [ threshold ])
    end

    def build_rejection(input, context)
      nonce = input["nonce"]
      raise Refusal.new("invalid_nonce") unless nonce.is_a?(String) && nonce.match?(/\A(0|[1-9]\d{0,77})\z/)
      raise Refusal.new("nonce_too_low") if nonce.to_i < context[:current_nonce]

      Built.new("rejection", { "nonce" => nonce }, context[:safe], 0, "0x", 0)
    end

    # The Safe's linked list: the sentinel precedes the head, otherwise the previous entry.
    def prev_owner(owners, owner)
      index = owners.index(owner) || raise(Refusal.new("owner_unknown"))
      index.zero? ? Address::SENTINEL : owners[index - 1]
    end

    def owner_call(kind, params, context, selector, types, values)
      Built.new(kind, params, context[:safe], 0, Abi.call(selector, types, values), 0)
    end

    def address!(value)
      Address.normalize(value)
    rescue Address::Invalid
      raise Refusal.new("invalid_address")
    end

    def recipient!(value, context)
      address = address!(value)
      forbidden = [ Address::ZERO, Address::SENTINEL, context[:safe], context[:token] ]
      raise Refusal.new("recipient_forbidden") if forbidden.include?(address)

      address
    end

    def new_owner!(value, context)
      address = address!(value)
      raise Refusal.new("owner_forbidden") if [ Address::ZERO, Address::SENTINEL, context[:safe] ].include?(address)
      raise Refusal.new("owner_exists") if context[:owners].include?(address)

      address
    end

    def existing_owner!(value, context)
      address = address!(value)
      raise Refusal.new("owner_unknown") unless context[:owners].include?(address)

      address
    end

    def amount!(value)
      raise Refusal.new("invalid_amount") unless value.is_a?(String) && value.match?(/\A[1-9]\d{0,77}\z/)

      amount = value.to_i
      raise Refusal.new("invalid_amount") if amount > Abi::UINT256_MAX

      amount
    end

    def threshold!(value, maximum)
      threshold = ThresholdRules.parse(value)
      raise Refusal.new("threshold_out_of_range") unless threshold&.between?(1, maximum)

      threshold
    end
  end
end
