require "test_helper"

class ChainSyncSchedulerJobTest < ActiveJob::TestCase
  test "enqueues active funds and deploying funds on enabled chains only" do
    active = accounts(:one)
    deploying = accounts(:two)
    activate_safe(active, owners: [ address_of(:alice) ], threshold: 1)
    activate_safe(deploying, owners: [ address_of(:bob) ], threshold: 1, safe: "0x2222222222222222222222222222222222222222")
    deploying.update_columns(safe_status: "deploying")
    disabled = Account.create!(name: "Mainnet fonds", chain_id: 8453, token_address: Chain::Registry.all["base"].token.address,
                               safe_address: "0x3333333333333333333333333333333333333333", safe_salt_nonce: 1, safe_threshold: 1,
                               safe_owners: [ address_of(:bob) ], safe_status: "active")
    Account.create!(name: "Concept fonds")

    ChainSyncSchedulerJob.perform_now

    assert_enqueued_with(job: ChainSyncJob, args: [ active.id ])
    assert_enqueued_with(job: SafeDeploymentVerificationJob, args: [ deploying.id ])
    assert_enqueued_jobs 2
    assert disabled.persisted?
  end

  test "cleanup removes only old challenges" do
    session = users(:one).sessions.create!
    old = WalletChallenge.issue_handoff!(user: users(:one), session: session).first
    old.update_columns(expires_at: 2.days.ago)
    recent = WalletChallenge.issue_handoff!(user: users(:one), session: session).first
    WalletChallengeCleanupJob.perform_now
    assert_not WalletChallenge.exists?(old.id)
    assert WalletChallenge.exists?(recent.id)
  end

  test "recurring.yml schedules the chain jobs" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    assert_equal "ChainSyncSchedulerJob", config["production"]["chain_sync_scheduler"]["class"]
    assert_equal "WalletChallengeCleanupJob", config["production"]["wallet_challenge_cleanup"]["class"]
    assert config["production"].key?("clear_solid_queue_finished_jobs")
  end
end
