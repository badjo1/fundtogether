class Account < ApplicationRecord
  SAFE_STATUSES = %w[draft deploying active].freeze
  # These decide where the money lives, so they cannot move once a Safe may exist.
  IMMUTABLE_AFTER_DEPLOYMENT = %w[chain_id token_address safe_address safe_salt_nonce safe_owners
                                  safe_threshold safe_group_uuid].freeze

  # Before the dependent callbacks below, or the children would already be gone.
  before_destroy :refuse_destroy_with_safe, prepend: true

  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :invitations, dependent: :destroy
  has_many :users_with_this_as_current, class_name: "User", foreign_key: :current_account_id,
           inverse_of: :current_account, dependent: :nullify
  has_many :safe_proposals, dependent: :destroy
  has_many :chain_events, dependent: :destroy

  normalizes :name, :description, with: ->(value) { SafeText.clean(value) }

  # Validations
  validates :name, presence: true, length: { minimum: 3, maximum: 100 }
  validates :description, length: { maximum: 2_000 }
  validates :safe_status, inclusion: { in: SAFE_STATUSES }
  validates :token_address, format: { with: Chain::Address::LOWER }, allow_nil: true
  validates :safe_address, format: { with: Chain::Address::LOWER }, allow_nil: true,
                           uniqueness: { scope: :chain_id }
  validates :deploy_tx_hash, format: { with: Chain::Hex::HASH }, allow_nil: true
  validate :safe_settings_immutable_after_deployment, on: :update

  scope :safe_active, -> { where(safe_status: "active") }
  scope :safe_deploying, -> { where(safe_status: "deploying") }

  def name
    SafeText.clean(super)
  end

  def description
    SafeText.clean(super)
  end

  def safe_draft?
    safe_status == "draft"
  end

  def safe_deploying?
    safe_status == "deploying"
  end

  def safe_active?
    safe_status == "active"
  end

  def chain
    Chain::Registry.fetch(chain_id) if chain_id
  end

  def active_users
    users.merge(AccountMembership.active)
  end

  def active_members_count
    active_users.count
  end

  def admins
    active_users.merge(AccountMembership.admins)
  end

  def active_admin?(user)
    admins.exists?(user&.id)
  end

  def add_member(user, role: "member")
    account_memberships.create!(
      user: user,
      role: role,
      active: true,
      joined_at: Time.current
    )
  end

  # Who each on-chain owner maps to right now. App roles and wallets never change the chain, so this
  # is how a removed member or an unlinked wallet shows up as a gap (docs/ARCHITECTURE.md, Authorization).
  def owner_details(owners)
    wallets = Wallet.active.where(address: owners).includes(:user).index_by(&:address)
    active_ids = account_memberships.active.pluck(:user_id)
    owners.map do |address|
      user = wallets[address]&.user
      { address: address, user_id: user&.id, name: user&.display_name, verified_wallet: user.present?,
        active_member: user.present? && active_ids.include?(user.id) }
    end
  end

  # Names shared by more than one active member, compared loosely. Two people looking alike on a signing
  # page is how the wrong key gets approved (docs/SECURITY_REVIEW.md, M6).
  def duplicate_member_names
    active_users.pluck(:name).group_by { |name| SafeText.comparable(name) }.select { |_, names| names.size > 1 }.keys
  end

  private

  def refuse_destroy_with_safe
    return if safe_draft?

    errors.add(:base, "Dit fonds heeft een Safe op de blockchain en kan niet worden verwijderd.")
    throw :abort
  end

  def safe_settings_immutable_after_deployment
    return if safe_status_was == "draft"

    IMMUTABLE_AFTER_DEPLOYMENT.each do |field|
      errors.add(field, "kan niet meer wijzigen nadat de Safe is aangemaakt") if attribute_changed?(field)
    end
  end
end
