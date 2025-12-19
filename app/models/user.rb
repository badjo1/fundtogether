class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships
  has_many :sent_transactions, class_name: 'Transaction', 
           foreign_key: 'from_user_id', dependent: :nullify
  has_many :received_transactions, class_name: 'Transaction', 
           foreign_key: 'to_user_id', dependent: :nullify
  belongs_to :current_account, class_name: 'Account', optional: true


  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :wallet_address, uniqueness: true, allow_nil: true,
            format: { with: /\A0x[a-fA-F0-9]{40}\z/, message: "must be a valid Ethereum address" },
            if: -> { wallet_address.present? }
  
  # Scopes
  scope :active_in_account, ->(account) { 
    joins(:account_memberships)
      .where(account_memberships: { account_id: account.id, active: true }) 
  }

  # Instance methods
  def transactions_in_account(account)
    Transaction.where(account: account)
               .where('from_user_id = ? OR to_user_id = ?', id, id)
  end
  
  def balance_in_account(account)
    account_memberships.find_by(account: account)&.balance_cents || 0
  end
  
  def role_in_account(account)
    account_memberships.find_by(account: account)&.role
  end
  
  def admin_in_account?(account)
    role_in_account(account) == 'admin'
  end
  
  def active_in_account?(account)
    account_memberships.find_by(account: account)&.active?
  end
  
  def display_name
    name || email_address.split('@').first
  end
  
  def short_address
    return 'Not connected' unless wallet_address
    "#{wallet_address[0..5]}...#{wallet_address[-4..]}"
  end
  
   # Wissel naar een andere account
  def switch_to_account(account)
    return false unless accounts.include?(account)
    update(current_account: account)
  end

  # Stel eerste account in als current als er geen is
  def ensure_current_account
    update(current_account: accounts.first) if current_account.nil? && accounts.any?
  end

end




