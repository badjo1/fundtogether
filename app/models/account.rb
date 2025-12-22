class Account < ApplicationRecord
  attr_accessor :min_deposit, :auto_convert, :notifications

  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :transactions, dependent: :destroy
  has_many :invitations, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { minimum: 3, maximum: 100 }
  # validates :wallet_address, presence: true, uniqueness: true,
  #           format: { with: /\A0x[a-fA-F0-9]{40}\z/, message: "must be a valid Ethereum address" }
  validates :split_method, presence: true

  # Enums
  enum :split_method, { equal: "equal", proportional: "proportional", manual: "manual", percentage: "percentage" }

  # Callbacks
  before_validation :set_defaults, on: :create

  # Scopes
  scope :active, -> { joins(:account_memberships).where(account_memberships: { active: true }).distinct }

  # Instance methods - UPDATED: member → user
  def total_balance
    account_memberships.sum(:balance_cents)
  end

  def total_balance_euros
    total_balance / 100.0
  end

  def active_users
    users.joins(:account_memberships)
         .where(account_memberships: { account_id: id, active: true })
  end

  def active_members_count
    active_users.count
  end

  def admins
    users.joins(:account_memberships)
         .where(account_memberships: { account_id: id, role: "admin" })
  end

  def user_balance(user)
    user_balance_cents = account_memberships.find_by(user: user)&.balance_cents || 0
    user_balance_cents / 100.0
  end

  def user_role(user)
    account_memberships.find_by(user: user)&.role
  end

  def add_member(user, role: "member", balance: 0)
    account_memberships.create!(
      user: user,
      role: role,
      balance_cents: balance,
      active: true,
      joined_at: Time.current
    )
  end

  def remove_user(user)
    account_memberships.find_by(user: user)&.update(active: false)
  end

  def monthly_expenses_cents(month = Time.current.month, year = Time.current.year)
    start_date = Date.new(year, month).beginning_of_month
    end_date = Date.new(year, month).end_of_month

    transactions.where(
      transaction_type: "expense",
      status: "confirmed",
      created_at: start_date..end_date
    ).sum(:amount_cents)
  end

  def monthly_expenses_euros(month = Time.current.month, year = Time.current.year)
    monthly_expenses_cents(month, year) / 100.0
  end

  # Alias for backwards compatibility
  def monthly_expenses(month = Time.current.month, year = Time.current.year)
    monthly_expenses_euros(month, year)
  end

  def recent_transactions(limit = 5)
    transactions.recent.limit(limit)
  end

  private

  def set_defaults
    self.auto_convert ||= true
    self.notifications ||= true
    self.min_deposit ||= 10.0
    self.split_method ||= "equal"
  end
end
