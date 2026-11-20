module Chain
  # The fund balance is balanceOf, read live. When the RPC fails the last live reading is returned
  # with its timestamp and labelled as such; with no earlier reading the amount is nil, never zero.
  # native_amount is the Safe's gas token, also live, and nil when it could not be read.
  module Balance
    module_function

    def read(account)
      reader = SafeReader.for_account(account)
      amount = reader.token_balance(account.token_address)
      account.update_columns(balance_cached: amount, balance_cached_at: Time.current)
      { source: "live", amount: amount.to_s, as_of: account.balance_cached_at.utc.iso8601, native_amount: native(reader) }
    rescue Rpc::Error
      { source: account.balance_cached_at ? "cached" : "unavailable", amount: account.balance_cached&.to_i&.to_s,
        as_of: account.balance_cached_at&.utc&.iso8601, native_amount: nil,
        message: "De actuele stand kon niet worden opgehaald." }
    end

    def native(reader)
      reader.native_balance.to_s
    rescue Rpc::Error
      nil
    end
    private_class_method :native
  end
end
