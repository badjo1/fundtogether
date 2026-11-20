# A proposal as one user sees it right now. Computed on every request from live owners, threshold and
# nonce (docs/ARCHITECTURE.md: never store "ready"). Without a snapshot nothing is ever called ready.
class ProposalView
  attr_reader :proposal, :live

  CLOSED_PAGE_SIZE = 25
  CLOSED_STATES = %w[executed failed superseded cancelled].freeze

  # Everything open (bounded by the caps in Chain::ProposalCreator), which is what needs live work.
  def self.open_for(account, user, snapshot)
    build_all(account.safe_proposals.open.includes(:proposer, :account, safe_signatures: :user).order(nonce: :desc, id: :desc).to_a, account, user, snapshot)
  end

  # One page of what is over. Stored outcome only: nothing here costs a recovery or an RPC read.
  def self.closed_for(account, user, snapshot, page: 1, state: nil)
    scope = account.safe_proposals.where(state: state || CLOSED_STATES)
    rows = scope.includes(:proposer, :account).order(nonce: :desc, id: :desc).limit(CLOSED_PAGE_SIZE + 1).offset((page - 1) * CLOSED_PAGE_SIZE).to_a
    build_all(rows, account, user, snapshot)
  end

  def self.build_all(proposals, account, user, snapshot)
    addresses = user.wallets.active.pluck(:address)
    context = snapshot && Chain::ProposalContext.new(account, snapshot)
    proposals.map { |proposal| new(proposal, addresses, snapshot, context: context) }
  end
  private_class_method :build_all

  def initialize(proposal, my_addresses, snapshot, context: nil)
    @proposal = proposal
    @my_addresses = my_addresses
    @snapshot = snapshot
    @live = snapshot && Chain::ProposalStatus.new(proposal, snapshot, context: context).as_json
  end

  def live?
    live.present?
  end

  def open?
    proposal.open?
  end

  def ready?
    live? && live[:executable] == true
  end

  def reason
    live && live[:reason]
  end

  # An owner wallet of mine that has not signed, on a proposal that can still be executed.
  def signable_addresses
    return [] unless live? && open? && %w[not_enough_signatures waiting_for_earlier_nonce].include?(reason)

    @my_addresses & (live[:owners] - live[:valid_signers])
  end

  def needs_me?
    signable_addresses.any?
  end

  def i_signed?
    live? && (@my_addresses & live[:valid_signers]).any?
  end

  def warning?(code)
    live? && Array(live[:warnings]).include?(code)
  end

  def my_owner_addresses
    live? ? @my_addresses & live[:owners] : []
  end

  # needs_me, ready, waiting, stale, executed, failed, superseded or unknown. One proposal, one bucket.
  def bucket
    case proposal.state
    when "executed", "failed", "superseded", "cancelled" then proposal.state
    else open_bucket
    end
  end

  private

  def open_bucket
    return "unknown" unless live?
    return "ready" if ready?
    return "needs_me" if needs_me?
    return "insufficient" if reason == "insufficient_balance"

    %w[nonce_passed tampered calldata_stale].include?(reason) ? "stale" : "waiting"
  end
end
