module ProposalRendering
  extend ActiveSupport::Concern

  private

  def find_proposal(param = :id)
    @account.safe_proposals.find_by(id: params[param]) || raise(Chain::Refusal.new("proposal_not_found", status: :not_found))
  end

  # nil on an outage: the stored proposal stays readable, and live state says it is unknown.
  def live_snapshot
    return nil unless @account.safe_active?

    Chain::SafeReader.for_account(@account).snapshot
  rescue Chain::Rpc::Error => e
    Rails.logger.warn("[chain.api] live snapshot: #{e.class}")
    nil
  end

  def proposal_json(proposal, snapshot)
    chain = @account.chain
    { id: proposal.id, kind: proposal.kind, title: proposal.title, params: proposal.params, state: proposal.state,
      chain_id: @account.chain_id, safe_address: @account.safe_address, to: proposal.to, value: proposal.value.to_i.to_s,
      data: proposal.data, operation: proposal.operation, safe_tx_gas: "0", base_gas: "0", gas_price: "0",
      gas_token: Chain::Address::ZERO, refund_receiver: Chain::Address::ZERO, nonce: proposal.nonce.to_i.to_s,
      safe_tx_hash: proposal.safe_tx_hash,
      token: { address: chain.token.address, symbol: chain.token.symbol, decimals: chain.token.decimals },
      signatures: proposal.safe_signatures.sort_by { |row| row.signer_address.delete_prefix("0x").to_i(16) }.map { |row| signature_json(row) },
      execution_tx_hash: proposal.execution_tx_hash, executed_at: proposal.executed_at&.utc&.iso8601,
      proposer: { id: proposal.proposer_id, name: proposal.proposer.display_name },
      created_at: proposal.created_at.utc.iso8601, live: live_json(proposal, snapshot) }
  end

  def signature_json(row)
    { signer: row.signer_address, signature: row.signature, user_id: row.user_id, name: row.user.display_name }
  end

  def live_json(proposal, snapshot)
    return { available: false, error: "rpc_unavailable", message: ChainApiController::RPC_MESSAGE } unless snapshot

    Chain::ProposalStatus.new(proposal, snapshot).as_json
  end
end
