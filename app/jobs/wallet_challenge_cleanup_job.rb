class WalletChallengeCleanupJob < ApplicationJob
  queue_as :default

  def perform
    WalletChallenge.where(expires_at: ...1.day.ago).delete_all
    Session.expired.find_each(&:destroy)
  end
end
