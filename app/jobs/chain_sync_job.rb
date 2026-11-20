class ChainSyncJob < ApplicationJob
  queue_as :default

  # A sync running or queued already covers what this one would do, so nothing is lost by dropping it.

  limits_concurrency to: 1, key: ->(account_id, **) { "chain_sync_#{account_id}" }, duration: 10.minutes, on_conflict: :discard

  retry_on Chain::Rpc::Error, wait: :polynomially_longer, attempts: 3
  discard_on Chain::Registry::ChainDisabled

  # tx_hash is a hint from a client: it says where to look first and credits nothing by itself.
  def perform(account_id, tx_hash: nil)
    account = Account.find_by(id: account_id)
    return unless account&.safe_active?

    sync = Chain::LogSync.new(account)
    sync.ingest_receipt(tx_hash) if tx_hash
    sync.call
  end
end
