module Chain
  # Independently decides, from the chain, whether a fund's Safe may become active. The client's
  # deploy_tx_hash is never evidence: code at the predicted CREATE2 address plus the live checks
  # are. Because the owners are inside the salt, "Create2 call failed" just means someone deployed
  # the identical Safe, and this verifier treats that as success. A nonce above 0 is not refused:
  # it only says the identical Safe was already used, and the checks below read its current state.
  class DeploymentVerifier
    Result = Data.define(:verified, :failures, :deployed) do
      def verified?
        verified
      end
    end

    STALE_AFTER = 24.hours
    MAX_ATTEMPTS = 30
    MAX_BACKOFF = 1.hour

    def initialize(account, rpc: nil)
      @account = account
      @chain = account.chain
      @rpc = rpc || Rpc.for(@chain)
      @reader = SafeReader.new(chain: @chain, safe: account.safe_address, rpc: @rpc)
    end

    def call
      return Result.new(true, [], true) if @account.safe_active?

      return handle_no_code unless deployed?

      failures = check_contract
      if failures.empty?
        activate
        Result.new(true, [], true)
      else
        @account.update!(safe_verification_error: failures.join(","))
        Rails.logger.warn("[chain.deploy] account=#{@account.id} failed verification: #{failures.join(',')}")
        Result.new(false, failures, true)
      end
    end

    # For the scheduler: bounded, and later each time, so a fund stuck in deploying costs less and less.
    # update_columns: STALE_AFTER counts from the last real change, not from the last look.
    def scheduled_check
      attempts = @account.safe_verification_attempts
      return return_to_draft("deploy_tx_not_found") if attempts >= MAX_ATTEMPTS

      wait = [ (2**attempts).minutes, MAX_BACKOFF ].min
      @account.update_columns(safe_verification_attempts: attempts + 1, safe_verification_next_at: wait.from_now)
      call
    end

    private

    def deployed?
      @reader.code != "0x"
    end

    def check_contract
      failures = []
      failures << "singleton_mismatch" unless @reader.singleton == @chain.singleton
      failures << "owners_mismatch" unless @reader.owners == @account.safe_owners
      failures << "threshold_mismatch" unless @reader.threshold == @account.safe_threshold
      failures << "modules_present" unless @reader.modules.empty?
      failures << "guard_present" unless @reader.guard == Address::ZERO
      failures << "fallback_handler_mismatch" unless @reader.fallback_handler == @chain.fallback_handler
      failures
    end

    def activate
      @account.update!(safe_status: "active", safe_verified_at: Time.current, safe_verification_error: nil,
                       safe_verification_attempts: 0, safe_verification_next_at: nil)
    end

    # No Safe at the address. A reverted or long-lost transaction hands the fund back to draft, so
    # the admin can try again; anything else just waits.
    def handle_no_code
      if @account.safe_deploying?
        receipt = @account.deploy_tx_hash ? @rpc.get_receipt(@account.deploy_tx_hash) : nil
        if receipt&.fetch(:status)&.zero?
          return_to_draft("deploy_tx_reverted")
        elsif receipt.nil? && @account.updated_at < STALE_AFTER.ago
          return_to_draft("deploy_tx_not_found")
        end
      end
      Result.new(false, [ "no_code" ], false)
    end

    def return_to_draft(reason)
      @account.update!(safe_status: "draft", deploy_tx_hash: nil, safe_verification_error: reason,
                       safe_verification_attempts: 0, safe_verification_next_at: nil)
    end
  end
end
