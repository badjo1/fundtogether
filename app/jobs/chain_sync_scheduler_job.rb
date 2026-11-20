# Recurring (config/recurring.yml): keeps every enabled fund's chain data moving.
class ChainSyncSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    chain_ids = Chain::Registry.enabled.map(&:chain_id)
    Account.safe_active.where(chain_id: chain_ids).in_batches do |batch|
      batch.ids.each { |id| ChainSyncJob.perform_later(id) }
    end
    Account.safe_deploying.where(chain_id: chain_ids).where("safe_verification_next_at IS NULL OR safe_verification_next_at <= ?", Time.current).in_batches do |batch|
      batch.ids.each { |id| SafeDeploymentVerificationJob.perform_later(id) }
    end
  end
end
