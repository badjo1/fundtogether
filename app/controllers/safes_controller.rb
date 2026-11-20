class SafesController < ChainApiController
  before_action :set_fund
  before_action :require_fund_admin, only: [ :create, :update ]
  rate_limit to: 20, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: [ :create, :update ]

  def show
    render json: deployment_json(live: true)
  end

  def create
    Chain::SafeConfigurator.new(@account).call(
      chain_id: params[:chain_id], token_address: params[:token_address], owners: params[:owners],
      threshold: params[:threshold], acknowledge_risk: params[:acknowledge_risk]
    )
    render json: deployment_json, status: :created
  end

  # Records the browser's transaction as a hint and verifies straight away. deploy_tx_hash may be
  # omitted after a "Create2 call failed" pre-flight: the verifier looks at the address either way.
  def update
    raise Chain::Refusal.new("safe_not_configured", status: :conflict) if @account.safe_address.blank?

    record_transaction(params[:deploy_tx_hash]) if params.key?(:deploy_tx_hash)
    verify
    render json: deployment_json
  end

  private

  def record_transaction(hash)
    down = hash.is_a?(String) ? hash.downcase : nil
    raise Chain::Refusal.new("invalid_tx_hash") unless Chain::Hex.hash?(down)
    return if @account.safe_active? || (@account.safe_deploying? && @account.deploy_tx_hash == down)

    # A claim costs nothing, and every deploying fund costs RPC reads on a schedule (SECURITY_REVIEW M3). So the
    # hash has to exist and be this fund's deployment. Not found yet is not an error: the client asks again
    # after the receipt, and the address check below works without a hash anyway.
    tx = Chain::Rpc.for(@account.chain).get_transaction(down)
    return unless tx
    raise Chain::Refusal.new("deploy_tx_mismatch") unless tx[:to] == @account.chain.factory && tx[:input] == Chain::Create2.calldata(@account)

    @account.update!(safe_status: "deploying", deploy_tx_hash: down, safe_verification_error: nil,
                     safe_verification_attempts: 0, safe_verification_next_at: nil)
  rescue Chain::Rpc::Error => e
    Rails.logger.warn("[chain.deploy] hash check deferred: #{e.class}")
  end

  # An RPC outage leaves the fund in deploying: the job finishes the check, so this is not an error.
  def verify
    Chain::DeploymentVerifier.new(@account).call
  rescue Chain::Rpc::Error => e
    Rails.logger.warn("[chain.deploy] verify deferred: #{e.class}")
    SafeDeploymentVerificationJob.perform_later(@account.id) if @account.safe_deploying?
  end

  def deployment_json(live: false)
    chain = @account.chain
    return unconfigured_json unless chain

    { status: @account.safe_status, chain_id: @account.chain_id, chain_name: chain.name, testnet: chain.testnet?,
      safe_address: @account.safe_address, owners: @account.safe_owners, threshold: @account.safe_threshold,
      salt_nonce: @account.safe_salt_nonce&.to_i&.to_s, initializer: initializer(chain), factory: chain.factory,
      singleton: chain.singleton, fallback_handler: chain.fallback_handler, deploy_tx_hash: @account.deploy_tx_hash,
      verification_error: @account.safe_verification_error, verified_at: @account.safe_verified_at&.utc&.iso8601,
      token: token_json(chain) }.tap { |json| json[:live] = live_json if live && @account.safe_active? }
  end

  # Before the Safe is set up: the same keys, empty, plus what can be chosen.
  def unconfigured_json
    { status: @account.safe_status, chain_id: nil, safe_address: nil, owners: [], threshold: nil, salt_nonce: nil,
      initializer: nil, factory: nil, singleton: nil, fallback_handler: nil, deploy_tx_hash: nil,
      available_chains: Chain::Registry.enabled.map do |chain|
        { chain_id: chain.chain_id, name: chain.name, testnet: chain.testnet?, token: token_json(chain) }
      end }
  end

  def initializer(chain)
    return nil if @account.safe_owners.empty?

    Chain::Create2.initializer(owners: @account.safe_owners, threshold: @account.safe_threshold,
                               fallback_handler: chain.fallback_handler)
  end

  def token_json(chain)
    { address: chain.token.address, symbol: chain.token.symbol, decimals: chain.token.decimals }
  end

  # Live owners with who they map to now, so the UI can show a gap after a wallet or member change.
  def live_json
    snapshot = Chain::SafeReader.for_account(@account).snapshot
    { available: true, threshold: snapshot.threshold, nonce: snapshot.nonce.to_s, owners: @account.owner_details(snapshot.owners) }
  rescue Chain::Rpc::Error
    { available: false, error: "rpc_unavailable", message: RPC_MESSAGE }
  end
end
