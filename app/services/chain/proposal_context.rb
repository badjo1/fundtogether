module Chain
  # What many proposals in one request share, read once: open nonces and the Safe's balances. A list of ten
  # proposals costs one balanceOf, and nothing is read when nothing rendered needs it.
  class ProposalContext
    UNKNOWN = Object.new.freeze

    def initialize(account, snapshot)
      @account = account
      @snapshot = snapshot
    end

    def open_by_nonce
      @open_by_nonce ||= @account.safe_proposals.open.pluck(:nonce, :id).group_by { |nonce, _| nonce.to_i }
                                 .transform_values { |rows| rows.map(&:last) }
    end

    def siblings_of(proposal)
      open_by_nonce.fetch(proposal.nonce.to_i, []) - [ proposal.id ]
    end

    # An earlier nonce has nothing open: nothing in the app can fill it, so this one would wait forever.
    def gap_before?(proposal)
      (@snapshot.nonce...proposal.nonce.to_i).any? { |nonce| !open_by_nonce.key?(nonce) }
    end

    # Integer, or nil when it could not be read.
    def token_balance
      read(:token) { SafeReader.for_account(@account).token_balance(@account.token_address) }
    end

    def native_balance
      read(:native) { SafeReader.for_account(@account).native_balance }
    end

    private

    def read(key)
      @balances ||= {}
      return @balances[key] if @balances.key?(key)

      @balances[key] = begin
        yield
      rescue Rpc::Error => e
        Rails.logger.warn("[chain.status] balance: #{e.class}")
        nil
      end
    end
  end
end
