require "openssl"

class SafeSignature < ApplicationRecord
  belongs_to :safe_proposal
  belongs_to :user

  attr_readonly :signer_address, :signature, :safe_proposal_id

  validates :signer_address, format: { with: Chain::Address::LOWER }
  validates :signature, format: { with: /\A0x[0-9a-f]{128}(1b|1c)\z/ }
  validates :signer_address, uniqueness: { scope: :safe_proposal_id }

  # Keyed, so a changed database row does not pass without the server's secret.
  def self.mac_for(hash, signer, signature)
    @mac_key ||= Rails.application.key_generator.generate_key("safe_signature_verification", 32)
    OpenSSL::HMAC.hexdigest("SHA256", @mac_key, "#{hash}|#{signer}|#{signature}")
  end

  # Recovery costs about 80 ms in pure Ruby and its input never changes, so it runs once for each row:
  # at receipt, or the first time an older row is read. docs/SECURITY_REVIEW.md, H4.
  def verified_for?(hash)
    expected = self.class.mac_for(hash, signer_address, signature)
    return true if verification_mac && ActiveSupport::SecurityUtils.secure_compare(verification_mac, expected)
    return false unless Chain::Signature.recover_hash(hash, signature) == signer_address

    update_column(:verification_mac, expected)
    true
  rescue Chain::Signature::Invalid
    false
  end
end
