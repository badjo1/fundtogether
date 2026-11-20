module Chain
  # POST /accounts/:id/proposals. Everything comes from typed parameters plus live chain state;
  # the row lock on the fund serialises nonce assignment. Queue rules: docs/ARCHITECTURE.md.
  class ProposalCreator
    OPEN_PER_MEMBER = 5
    OPEN_PER_OWNER = 10
    OPEN_PER_FUND = 30

    def initialize(account:, proposer:)
      @account = account
      @proposer = proposer
    end

    def call(kind:, title:, params:, acknowledge_risk: false)
      raise Refusal.new("safe_not_active", status: :conflict) unless @account.safe_active?

      clean_title = title.is_a?(String) ? SafeText.clean(title) : ""
      raise Refusal.new("invalid_title") if clean_title.empty? || clean_title.length > SafeProposal::TITLE_MAX

      raise Refusal.new("unexpected_param") unless params.is_a?(Hash)

      # Before any network call: unknown kinds and bad input never cost an RPC read.
      raise Refusal.new("unknown_kind") unless ProposalBuilder::FIELDS.key?(kind.to_s)

      snapshot = SafeReader.for_account(@account).snapshot
      built = ProposalBuilder.build(kind: kind, params: params, safe: @account.safe_address, token: @account.token_address,
                                    owners: snapshot.owners, threshold: snapshot.threshold, current_nonce: snapshot.nonce)
      check_owner_rules(built, snapshot, acknowledge_risk)
      create(built, clean_title, snapshot)
    end

    private

    def check_owner_rules(built, snapshot, acknowledge_risk)
      eligibility = OwnerEligibility.new(@account)
      case built.kind
      when "add_owner"
        eligibility.check_new_owner!(built.params["owner"], other_owners: snapshot.owners)
        check_threshold(snapshot.owners.length + 1, built, acknowledge_risk)
      when "remove_owner"
        check_threshold(snapshot.owners.length - 1, built, acknowledge_risk)
      when "swap_owner"
        eligibility.check_new_owner!(built.params["new_owner"], other_owners: snapshot.owners - [ built.params["old_owner"] ])
      when "change_threshold"
        check_threshold(snapshot.owners.length, built, acknowledge_risk)
      end
    end

    def check_threshold(owner_count, built, acknowledge_risk)
      ThresholdRules.check!(owner_count: owner_count, threshold: built.params["threshold"],
                            acknowledge_risk: acknowledge_risk == true || acknowledge_risk == "true")
    end

    def create(built, title, snapshot)
      @account.with_lock do
        refuse_over_cap(built, snapshot)
        nonce = nonce_for(built, snapshot)
        tx = { to: built.to, value: built.value, data: built.data, operation: built.operation, nonce: nonce }
        SafePolicy.check!(tx, safe: @account.safe_address, token: @account.token_address, current_nonce: snapshot.nonce)
        hash = Eip712.safe_tx_hash(chain_id: @account.chain_id, safe: @account.safe_address, **tx)
        @account.safe_proposals.create!(proposer: @proposer, kind: built.kind, title: title, params: built.params,
                                        to: built.to, value: built.value, data: built.data, operation: built.operation,
                                        nonce: nonce, safe_tx_hash: hash)
      end
    rescue ActiveRecord::RecordNotUnique
      raise Refusal.new("proposal_duplicate", status: :conflict)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.of_kind?(:safe_tx_hash, :taken)

      raise Refusal.new("proposal_duplicate", status: :conflict)
    end

    def proposer_is_owner?(snapshot)
      return @proposer_is_owner if defined?(@proposer_is_owner)

      @proposer_is_owner = @proposer.wallets.active.where(address: snapshot.owners).exists?
    end

    # Bounds what one member can leave lying around, and so what every signing page has to compute. An owner
    # change or rejection from an owner or admin always goes in: that is how a group gets out of trouble.
    def refuse_over_cap(built, snapshot)
      escape_route = SafeProposal::OWNER_KINDS.include?(built.kind) || built.kind == "rejection"
      open_now = @account.safe_proposals.open.where(nonce: snapshot.nonce..)
      owner = proposer_is_owner?(snapshot)

      unless escape_route && (owner || @account.active_admin?(@proposer))
        limit = owner ? OPEN_PER_OWNER : OPEN_PER_MEMBER
        raise Refusal.new("too_many_open_proposals", status: :too_many_requests) if open_now.where(proposer: @proposer).count >= limit
      end
      return if escape_route || owner

      raise Refusal.new("fund_queue_full", status: :too_many_requests) if open_now.count >= OPEN_PER_FUND
    end

    # Only owners claim nonces beyond the next, and only what an owner proposed or signed holds a slot, so
    # junk from a member cannot push anyone back. An owner change always takes the live nonce: it can never be
    # queued behind anything, and two of them exclude each other instead of making one unexecutable.
    def nonce_for(built, snapshot)
      open_proposals = @account.safe_proposals.open
      if built.kind == "rejection"
        nonce = built.params["nonce"].to_i
        # A withdrawn proposal with signatures can still execute on-chain, so it can still be rejected.
        signed_cancelled = @account.safe_proposals.where(state: "cancelled", nonce: nonce).where.not(kind: "rejection").where(id: SafeSignature.select(:safe_proposal_id))
        target = open_proposals.where(nonce: nonce).where.not(kind: "rejection").exists? || signed_cancelled.exists?
        raise Refusal.new("rejection_without_target") unless target

        nonce
      elsif SafeProposal::OWNER_KINDS.include?(built.kind) || !proposer_is_owner?(snapshot)
        snapshot.nonce
      else
        lowest_free_nonce(open_proposals, snapshot)
      end
    end

    def lowest_free_nonce(open_proposals, snapshot)
      owner_users = Wallet.active.where(address: snapshot.owners).select(:user_id)
      held = open_proposals.where(nonce: snapshot.nonce..)
                           .where("safe_proposals.proposer_id IN (?) OR EXISTS (SELECT 1 FROM safe_signatures WHERE safe_signatures.safe_proposal_id = safe_proposals.id)", owner_users)
                           .distinct.pluck(:nonce).map(&:to_i).to_set
      nonce = snapshot.nonce
      nonce += 1 while held.include?(nonce)
      nonce
    end
  end
end
