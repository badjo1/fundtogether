# app/models/transaction.rb (update associations and methods)
class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :from_user, class_name: "User", optional: true
  belongs_to :to_user, class_name: "User", optional: true

  # Validations
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true
  validates :token, presence: true
  validates :status, presence: true
  validates :description, presence: true
  validates :tx_hash, uniqueness: true, allow_nil: true,
            format: { with: /\A0x[a-fA-F0-9]{64}\z/, message: "must be a valid transaction hash" },
            if: -> { tx_hash.present? }
  validate :to_user_present_for_transfers

  # Enums
  enum :transaction_type, { deposit: "deposit", expense: "expense", transfer: "transfer" }

  enum :status, { pending: "pending", confirmed: "confirmed", failed: "failed", cancelled: "cancelled" }

  enum :token, { eure: "EURe", dummy: "DUMMY", eth: "ETH" }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_commit :update_user_balances, if: :saved_change_to_status?, on: [ :create, :update ]
  after_commit :update_user_balances, if: :saved_change_to_id?, on: :create

  # Scopes
  scope :deposits, -> { where(transaction_type: "deposit") }
  scope :expenses, -> { where(transaction_type: "expense") }
  scope :transfers, -> { where(transaction_type: "transfer") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :pending, -> { where(status: "pending") }
  scope :recent, -> { order(created_at: :desc) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }

  # Virtual attributes for euros
  def amount
    amount_cents / 100.0
  end

  def amount_euros=(value)
    self.amount_cents = (value.to_f * 100).round
  end

  def amount_euros
    amount
  end

  # Instance methods
  def confirm!
    update!(status: "confirmed")
  end

  def split_per_member
    return 0 unless transaction_type == "expense"
    return 0 if account.active_users.count.zero?

    case account.split_method
    when "equal"
      amount_cents / account.active_users.count
    when "proportional"
      total_balance = account.total_balance
      if total_balance > 0
        (amount_cents * (from_user.balance_in_account(account) / total_balance)).round
      else
        amount_cents / account.active_users.count
      end
    else
      amount_cents
    end
  end

  private

  def set_defaults
    self.status ||= "confirmed"  # Auto-confirm deposits/expenses
    self.token ||= "EURe"
  end

  def to_user_present_for_transfers
    if transaction_type == "transfer" && to_user_id.blank?
      errors.add(:to_user_id, "must be present for transfers")
    end
  end

  def update_user_balances
    return unless confirmed?

    case transaction_type
    when "deposit"
      membership = from_user.account_memberships.find_by(account: account)
      membership&.increment_balance(amount_cents)
    when "expense"
      # Split expense among ALL active members
      split_amount = split_per_member
      account.active_users.each do |user|
        membership = user.account_memberships.find_by(account: account)
        membership&.decrement_balance(split_amount)
      end
    when "transfer"
      from_membership = from_user.account_memberships.find_by(account: account)
      to_membership = to_user.account_memberships.find_by(account: account)
      from_membership&.decrement_balance(amount_cents)
      to_membership&.increment_balance(amount_cents)
    end
  end
end
