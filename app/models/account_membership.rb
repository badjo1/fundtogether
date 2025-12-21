# app/models/account_membership.rb (update associations)
class AccountMembership < ApplicationRecord
  belongs_to :account
  belongs_to :user
  
  # Validations
  validates :role, presence: true, inclusion: { in: %w[admin member viewer] }
  validates :balance_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: { scope: :account_id, message: "is already in this account" }
  
  # Enums
  enum :role, { admin: 'admin', member: 'member', viewer: 'viewer' }

  # Callbacks
  before_validation :set_defaults, on: :create
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: 'admin') }
  scope :members_only, -> { where(role: 'member') }
  
  # Instance methods
  def increment_balance(amount)
    increment!(:balance_cents, amount)
  end

  def decrement_balance(amount)
    decrement!(:balance_cents, amount)
  end

  def admin?
    role == 'admin'
  end
  
  private

  def set_defaults
    self.balance_cents ||= 0
    self.role ||= 'member'
    self.active = true if active.nil?
    self.joined_at ||= Time.current
  end
end