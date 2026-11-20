class SafeProposal < ApplicationRecord
  KINDS = %w[transfer_token transfer_native add_owner remove_owner swap_owner change_threshold rejection].freeze
  OWNER_KINDS = %w[add_owner remove_owner swap_owner change_threshold].freeze
  STATES = %w[open executed failed superseded cancelled].freeze
  TITLE_MAX = 120

  belongs_to :account
  belongs_to :proposer, class_name: "User"
  belongs_to :cancelled_by, class_name: "User", optional: true
  has_many :safe_signatures, dependent: :destroy
  has_many :chain_events, dependent: :nullify

  # What was hashed and possibly signed never changes.
  attr_readonly :account_id, :kind, :to, :value, :data, :operation, :nonce, :safe_tx_hash, :params, :proposer_id

  validates :kind, inclusion: { in: KINDS }
  validates :state, inclusion: { in: STATES }
  validates :title, presence: true, length: { maximum: TITLE_MAX }
  validates :to, format: { with: Chain::Address::LOWER }
  validates :operation, inclusion: { in: [ 0 ] }
  validates :safe_tx_hash, format: { with: Chain::Hex::HASH }, uniqueness: { scope: :account_id, conditions: -> { where.not(state: "cancelled") } }

  scope :open, -> { where(state: "open") }
  scope :owner_changes, -> { where(kind: OWNER_KINDS) }

  def title
    SafeText.clean(super)
  end

  def open?
    state == "open"
  end

  def cancelled?
    state == "cancelled"
  end

  def cancellable_by?(user, membership)
    open? && (membership&.admin? || (proposer_id == user.id && !membership&.viewer?))
  end

  def recomputed_safe_tx_hash
    Chain::Eip712.safe_tx_hash(chain_id: account.chain_id, safe: account.safe_address,
                               to: to, value: value.to_i, data: data, operation: operation, nonce: nonce.to_i)
  end

  def intact?
    recomputed_safe_tx_hash == safe_tx_hash
  end
end
