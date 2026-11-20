require "digest"

# Two kinds of one-time secret:
# - link: a server-composed SIWE-style message. The nonce is public; the signature is the proof.
# - handoff: a bearer token for a wallet's in-app browser. Only its SHA-256 is stored.
class WalletChallenge < ApplicationRecord
  CHALLENGE_LIFETIME = 10.minutes
  HANDOFF_LIFETIME = 5.minutes
  # How long a redeemed handoff keeps the wallet browser on the linking endpoints.
  HANDOFF_GRANT_LIFETIME = 15.minutes
  STATEMENT = "Koppel deze wallet aan je FundTogether-account. Dit kost niets en verplaatst geen geld.".freeze
  # Takes the account named in the message: a victim asked to sign for someone else's account can see it.

  belongs_to :user
  belongs_to :session

  validates :purpose, inclusion: { in: %w[link handoff] }
  validates :nonce, presence: true

  scope :expired, -> { where(expires_at: ...Time.current) }

  class << self
    def issue_link!(user:, session:, address:, chain_id:, now: Time.current)
      nonce = SecureRandom.alphanumeric(32)
      expires_at = now + CHALLENGE_LIFETIME
      create!(user: user, session: session, purpose: "link", address: address, chain_id: chain_id, nonce: nonce,
              expires_at: expires_at, message: compose_message(address, chain_id, nonce, now, expires_at, user.email_address))
    end

    # Returns [challenge, token]. The token exists only in this return value.
    def issue_handoff!(user:, session:)
      token = SecureRandom.urlsafe_base64(32)
      challenge = create!(user: user, session: session, purpose: "handoff", nonce: digest(token),
                          expires_at: HANDOFF_LIFETIME.from_now)
      [ challenge, token ]
    end

    def find_handoff(token)
      return nil unless token.is_a?(String) && token.length.between?(20, 100)

      where(purpose: "handoff").find_by(nonce: digest(token))
    end

    def digest(token)
      Digest::SHA256.hexdigest(token)
    end

    def origin
      Rails.configuration.x.wallet.origin
    end

    def domain
      URI(origin).then { |uri| uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}" }
    end

    private

    # EIP-4361 layout. ASCII only, because wallets render non-ASCII unreliably.
    def compose_message(address, chain_id, nonce, issued_at, expires_at, email)
      <<~MESSAGE.chomp
        #{domain} wants you to sign in with your Ethereum account:
        #{Chain::Address.checksum(address)}

        #{STATEMENT} Account: #{email}

        URI: #{origin}/wallets
        Version: 1
        Chain ID: #{chain_id}
        Nonce: #{nonce}
        Issued At: #{issued_at.utc.iso8601}
        Expiration Time: #{expires_at.utc.iso8601}
      MESSAGE
    end
  end

  def expired?
    expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  # Atomic, so two requests racing on one challenge cannot both win.
  def consume!
    self.class.where(id: id, consumed_at: nil).where("expires_at > ?", Time.current)
        .update_all(consumed_at: Time.current, updated_at: Time.current) == 1
  end

  def handoff_grant_active?
    purpose == "handoff" && consumed_at.present? && consumed_at > HANDOFF_GRANT_LIFETIME.ago && session.usable?
  end
end
