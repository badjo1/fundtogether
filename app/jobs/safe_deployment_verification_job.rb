class SafeDeploymentVerificationJob < ApplicationJob
  queue_as :default

  # An outage just delays activation: the recurring scheduler enqueues this again.
  retry_on Chain::Rpc::Error, wait: :polynomially_longer, attempts: 5
  discard_on Chain::Registry::ChainDisabled

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account&.safe_deploying?

    Chain::DeploymentVerifier.new(account).scheduled_check
  end
end
