class Wallet < ApplicationRecord
  KINDS = %w[eoa].freeze

  belongs_to :user

  attr_readonly :address, :user_id

  normalizes :address, with: ->(value) { value.to_s.strip.downcase }

  validates :address, presence: true, format: { with: Chain::Address::LOWER }
  validates :kind, inclusion: { in: KINDS }
  validates :label, length: { maximum: 50 }, allow_nil: true
  validates :verified_at, presence: true

  scope :active, -> { where(revoked_at: nil) }
  # The wallet that was verified and not yet revoked at a moment in time.
  scope :active_at, ->(time) { where(verified_at: ..time).where("revoked_at IS NULL OR revoked_at > ?", time) }

  def active?
    revoked_at.nil?
  end

  # Live: funds of this user whose Safe has this address as an owner. owner: nil means it could not
  # be read, which is not the same as "not an owner".
  def still_owner_of
    user.active_accounts.safe_active.filter_map do |account|
      owner = begin
        Chain::SafeReader.for_account(account).owners.include?(address)
      rescue Chain::Rpc::Error, Chain::Registry::ChainDisabled
        nil
      end
      { account_id: account.id, name: account.name, owner: owner } unless owner == false
    end
  end

  def revoke!
    update!(revoked_at: Time.current) if active?
  end
end
