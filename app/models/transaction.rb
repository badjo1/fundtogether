# app/models/transaction.rb (update associations and methods)
class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :from_user, class_name: 'User', optional: true
  belongs_to :to_user, class_name: 'User', optional: true
  
  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true, 
            inclusion: { in: %w[deposit expense transfer] }
  validates :token, presence: true, inclusion: { in: %w[EURe DUMMY ETH] }
  validates :status, presence: true, 
            inclusion: { in: %w[pending confirmed failed cancelled] }
  validates :tx_hash, uniqueness: true, allow_nil: true,
            format: { with: /\A0x[a-fA-F0-9]{64}\z/, message: "must be a valid transaction hash" },
            if: -> { tx_hash.present? }
  
  # Enums
  enum :transaction_type, [:deposit, :expense, :transfer]
  
  enum :status, [:pending, :confirmed, :failed, :cancelled]
  
  enum :token, [:eure, :dummy, :eth]
  
  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :update_user_balances, if: :confirmed?
  
  # Scopes
  scope :deposits, -> { where(transaction_type: 'deposit') }
  scope :expenses, -> { where(transaction_type: 'expense') }
  scope :transfers, -> { where(transaction_type: 'transfer') }
  scope :confirmed, -> { where(status: 'confirmed') }
  scope :pending, -> { where(status: 'pending') }
  scope :recent, -> { order(created_at: :desc) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }
  
  # Instance methods
  def confirm!
    update!(status: 'confirmed')
    update_user_balances
  end
  
  def split_amount
    return amount unless transaction_type == 'expense'
    
    case account.split_method
    when 'equal'
      amount / account.active_users.count
    when 'proportional'
      total_balance = account.total_balance
      (amount * (from_user.balance_in_account(account) / total_balance)) if total_balance > 0
    else
      amount
    end
  end
  
  private
  
  def set_defaults
    self.status ||= 'pending'
    self.token ||= 'EURe'
  end
  
  def update_user_balances
    return unless confirmed?
    
    case transaction_type
    when 'deposit'
      membership = from_user.account_memberships.find_by(account: account)
      membership&.increment_balance(amount)
    when 'expense'
      membership = from_user.account_memberships.find_by(account: account)
      membership&.decrement_balance(amount)
    when 'transfer'
      from_membership = from_user.account_memberships.find_by(account: account)
      to_membership = to_user.account_memberships.find_by(account: account)
      from_membership&.decrement_balance(amount)
      to_membership&.increment_balance(amount)
    end
  end
end
