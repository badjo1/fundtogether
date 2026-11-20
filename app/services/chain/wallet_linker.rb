module Chain
  # POST /wallets. Local crypto only. One active user per address; contract wallets are refused in
  # v1. The challenge is spent only after everything else passed, so an RPC outage can be retried.
  class WalletLinker
    # EIP-7702: an EOA with delegated code still signs with its own key, so it stays an EOA here.
    DELEGATED_EOA = /\A0xef0100[0-9a-f]{40}\z/

    class << self
      def address!(value)
        Address.normalize(value)
      rescue Address::Invalid
        raise Refusal.new("invalid_address")
      end

      # Enabled chains only, because a Safe can exist at an address on one chain and not another.
      def refuse_contract!(address)
        Registry.enabled.each do |chain|
          code = Rpc.for(chain).get_code(address)
          raise Refusal.new("contract_wallet_refused") unless code == "0x" || code.match?(DELEGATED_EOA)
        end
      end
    end

    def initialize(user:)
      @user = user
    end

    def call(address:, nonce:, signature:)
      raise Refusal.new("email_not_confirmed", status: :forbidden) unless @user.email_confirmed?

      address = self.class.address!(address)
      challenge = usable_challenge(nonce)
      raise Refusal.new("challenge_address_mismatch") unless challenge.address == address

      check_signature(challenge, signature)
      self.class.refuse_contract!(address)
      link(challenge, address)
    end

    private

    def usable_challenge(nonce)
      challenge = nonce.is_a?(String) ? @user.wallet_challenges.find_by(nonce: nonce, purpose: "link") : nil
      raise Refusal.new("challenge_invalid") unless challenge
      raise Refusal.new("challenge_consumed", status: :conflict) if challenge.consumed?
      raise Refusal.new("challenge_expired") if challenge.expired?

      challenge
    end

    def check_signature(challenge, signature)
      signer = Signature.recover_personal(challenge.message, signature)
      raise Refusal.new("wrong_signer") unless signer == challenge.address
    rescue Signature::Invalid
      raise Refusal.new("invalid_signature")
    end

    def link(challenge, address)
      Wallet.transaction do
        raise Refusal.new("challenge_consumed", status: :conflict) unless challenge.consume!

        owner = Wallet.active.find_by(address: address)
        raise Refusal.new("wallet_taken", status: :conflict) if owner && owner.user_id != @user.id

        next owner if owner

        @user.wallets.create!(address: address, verified_at: Time.current).tap do
          UserMailer.wallet_linked(@user, address).deliver_later
        end
      end
    rescue ActiveRecord::RecordNotUnique
      raise Refusal.new("wallet_taken", status: :conflict)
    end
  end
end
