module Chain
  # POST /proposals/:id/execution. The client's tx_hash is a hint for where to look: state changes only through
  # execution events found in that receipt, matched on safeTxHash. The chain nonce is not read here. With the scan
  # behind, "the nonce moved" says nothing about which proposal did it, so that conclusion is left to LogSync.
  class ExecutionCheck
    def initialize(proposal)
      @proposal = proposal
      @account = proposal.account
    end

    # "pending" not mined; "reverted" status 0, nothing consumed; "unrelated" no execution of this
    # proposal in that transaction; "executed"/"failed" what the chain's event says.
    def call(tx_hash)
      raise Refusal.new("invalid_tx_hash") unless tx_hash.is_a?(String) && Hex.hash?(tx_hash.downcase)

      receipt = LogSync.new(@account, rpc: Rpc.for(@account.chain)).ingest_receipt(tx_hash.downcase)
      return "pending" unless receipt
      return "reverted" if receipt[:status].zero?

      ProposalReconciler.new(@account).call(chain_nonce: nil)
      @proposal.reload
      @proposal.execution_tx_hash == tx_hash.downcase ? @proposal.state : "unrelated"
    end
  end
end
