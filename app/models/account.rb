class Account < ApplicationRecord
  attr_accessor :min_deposit, :auto_convert, :notifications

  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :transactions, dependent: :destroy
  has_many :invitations, dependent: :destroy
  belongs_to :current_account, class_name: 'Account', optional: true


  
  # Validations
  validates :name, presence: true, length: { minimum: 3, maximum: 100 }
  # validates :wallet_address, presence: true, uniqueness: true, 
  #           format: { with: /\A0x[a-fA-F0-9]{40}\z/, message: "must be a valid Ethereum address" }
  validates :split_method, presence: true, 
            inclusion: { in: %w[equal proportional manual percentage] }
  validates :min_deposit, numericality: { greater_than_or_equal_to: 0 }
  
  # Enums
  enum :split_method, [:equal, :proportional, :manual, :percentage]
  
  # Callbacks
  before_validation :set_defaults, on: :create
  
  # Scopes
  scope :active, -> { joins(:account_memberships).where(account_memberships: { active: true }).distinct }
  
  # Instance methods - UPDATED: member → user
  def total_balance
    account_memberships.sum(:balance)
  end
  
  def active_users
    users.joins(:account_memberships)
         .where(account_memberships: { account_id: id, active: true })
  end
  
  def admins
    users.joins(:account_memberships)
         .where(account_memberships: { account_id: id, role: 'admin' })
  end
  
  def user_balance(user)
    account_memberships.find_by(user: user)&.balance_cents || 0
  end
  
  def user_role(user)
    account_memberships.find_by(user: user)&.role
  end
  
  def add_member(user, role: 'member', balance: 0)
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
  
  def monthly_expenses(month = Time.current.month, year = Time.current.year)
    transactions.where(
      transaction_type: 'expense',
      created_at: Date.new(year, month).beginning_of_month..Date.new(year, month).end_of_month
    ).sum(:amount)
  end
  
  private
  
  def set_defaults
    self.auto_convert ||= true
    self.notifications ||= true
    self.min_deposit ||= 10.0
    self.split_method ||= 'equal'
  end
end
