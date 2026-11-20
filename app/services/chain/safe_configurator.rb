module Chain
  # Handles POST /accounts/:id/safe: validates intent, computes and stores the salt, owners and
  # predicted address. Nothing here touches money; the browser sends the deployment.
  class SafeConfigurator
    def initialize(account)
      @account = account
    end

    def call(chain_id:, token_address:, owners:, threshold:, acknowledge_risk:)
      chain = chain!(chain_id)
      token = token!(chain, token_address)
      owner_list = owners!(owners)
      threshold_value = ThresholdRules.parse(threshold)
      ThresholdRules.check!(owner_count: owner_list.length, threshold: threshold_value,
                            acknowledge_risk: acknowledge_risk == true || acknowledge_risk == "true")
      OwnerEligibility.new(@account).check_all!(owner_list)

      desired = { chain_id: chain.chain_id, token_address: token, safe_owners: owner_list, safe_threshold: threshold_value }
      unless already_this_configuration?(desired)
        raise Refusal.new("safe_locked", status: :conflict) unless @account.safe_draft?

        # Read first: if this fails, nothing is stored and the admin sees the outage.
        store(chain, desired, Rpc.for(chain).block_number)
      end
      # The identical Safe may already exist (same initializer, same address). Then this is done.
      DeploymentVerifier.new(@account).call if @account.safe_draft?
      @account
    end

    private

    def chain!(chain_id)
      id = chain_id.is_a?(String) && chain_id.match?(/\A\d{1,12}\z/) ? chain_id.to_i : chain_id
      Registry.fetch(id)
    rescue Registry::ChainDisabled
      raise Refusal.new("chain_not_enabled")
    end

    def token!(chain, token_address)
      token = Address.normalize(token_address)
      raise Refusal.new("token_not_allowed") unless token == chain.token.address

      token
    rescue Address::Invalid
      raise Refusal.new("invalid_address")
    end

    # Canonical ascending order: the order is part of the initializer, so it is fixed once.
    def owners!(owners)
      raise Refusal.new("owners_invalid") unless owners.is_a?(Array) && owners.any? && owners.length <= 50

      list = owners.map { |owner| Address.normalize(owner) }
      forbidden = [ Address::ZERO, Address::SENTINEL ]
      raise Refusal.new("owners_invalid") if list.uniq.length != list.length || list.intersect?(forbidden)

      Address.sort(list)
    rescue Address::Invalid
      raise Refusal.new("invalid_address")
    end

    def already_this_configuration?(desired)
      @account.safe_address.present? && desired.all? { |field, value| @account.public_send(field) == value }
    end

    def store(chain, desired, head)
      salt = Create2.salt_nonce(group_uuid: @account.safe_group_uuid, chain_id: chain.chain_id)
      initializer = Create2.initializer(owners: desired[:safe_owners], threshold: desired[:safe_threshold],
                                        fallback_handler: chain.fallback_handler)
      address = Create2.predict(factory: chain.factory, singleton: chain.singleton, initializer: initializer, salt_nonce: salt)
      # A cursor from before the address is known: nothing relevant can be older.
      @account.update!(desired.merge(safe_salt_nonce: salt, safe_address: address, deploy_tx_hash: nil,
                                     safe_verification_error: nil, synced_block: head, synced_block_hash: nil))
    end
  end
end
