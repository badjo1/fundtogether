module Chain
  # POST /proposals/:id/signatures. The hash is recomputed from stored fields, the signer recovered
  # locally, and the signer must be a verified wallet of this user and a live owner.
  class SignatureRecorder
    def initialize(proposal:, user:)
      @proposal = proposal
      @account = proposal.account
      @user = user
    end

    def call(signature)
      raise Refusal.new("proposal_not_open", status: :conflict) unless @proposal.open?
      raise Refusal.new("proposal_tampered", status: :conflict) unless @proposal.intact?

      signer, canonical = recover(signature)
      unless @user.wallets.active.exists?(address: signer)
        raise Refusal.new("signer_not_your_wallet", status: :forbidden)
      end

      snapshot = SafeReader.for_account(@account).snapshot
      raise Refusal.new("proposal_stale", status: :conflict) if @proposal.nonce.to_i < snapshot.nonce

      check_tx_policy(snapshot)
      raise Refusal.new("signer_not_owner", status: :forbidden) unless snapshot.owner?(signer)

      store(signer, canonical)
    end

    private

    def recover(signature)
      canonical = Signature.normalize(signature)
      [ Signature.recover_hash(@proposal.safe_tx_hash, canonical), canonical ]
    rescue Signature::Invalid
      raise Refusal.new("invalid_signature")
    end

    def check_tx_policy(snapshot)
      tx = { to: @proposal.to, value: @proposal.value, data: @proposal.data, operation: @proposal.operation,
             nonce: @proposal.nonce.to_i }
      SafePolicy.check!(tx, safe: @account.safe_address, token: @account.token_address, current_nonce: snapshot.nonce)
    end

    def store(signer, canonical)
      existing = @proposal.safe_signatures.find_by(signer_address: signer)
      return replay(existing, canonical) if existing

      @proposal.safe_signatures.create!(signer_address: signer, signature: canonical, user: @user,
                                        verification_mac: SafeSignature.mac_for(@proposal.safe_tx_hash, signer, canonical))
      @proposal
    rescue ActiveRecord::RecordNotUnique
      replay(@proposal.safe_signatures.find_by!(signer_address: signer), canonical)
    end

    # An exact replay is harmless and idempotent, a different encoding is not accepted.
    def replay(existing, canonical)
      raise Refusal.new("already_signed", status: :conflict) unless existing.signature == canonical

      @proposal
    end
  end
end
