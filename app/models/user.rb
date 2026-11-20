class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships
  has_many :active_memberships, -> { active }, class_name: "AccountMembership"
  has_many :active_accounts, through: :active_memberships, source: :account
  belongs_to :current_account, class_name: "Account", optional: true
  has_many :wallets, dependent: :destroy
  has_many :wallet_challenges, dependent: :destroy
  has_many :safe_proposals, foreign_key: :proposer_id, inverse_of: :proposer, dependent: :restrict_with_error
  has_many :safe_signatures, dependent: :restrict_with_error

  CONFIRMATION_LIFETIME = 24.hours
  ABANDONED_AFTER = 7.days

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(value) { SafeText.clean(value) }

  # Spent by confirming, and void if the address changes.
  generates_token_for :email_confirmation, expires_in: CONFIRMATION_LIFETIME do
    [ email_address, email_confirmed_at ]
  end

  scope :abandoned_unconfirmed, -> {
    where(email_confirmed_at: nil, created_at: ...ABANDONED_AFTER.ago)
      .where.missing(:account_memberships, :wallets, :safe_proposals, :safe_signatures)
  }

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # The membership that decides what this user may do right now. current_account_id
  # only says which fund they last chose; it never grants access by itself.
  def current_membership
    active_memberships.find_by(account_id: current_account_id) || active_memberships.order(:id).first
  end

  # The address is proven only by a token that went to it and came back with this account's password or
  # session, by a password reset, or by a link invitation's proof returning to the same browser.
  def email_confirmed?
    email_confirmed_at.present?
  end

  def confirm_email!
    update!(email_confirmed_at: Time.current) unless email_confirmed?
  end

  def send_email_confirmation
    update_column(:email_confirmation_sent_at, Time.current)
    UserMailer.email_confirmation(self).deliver_later
  end

  # Rows from before the input rule are neutralised here, so a screen never needs to know.
  def name
    SafeText.clean(super)
  end

  def display_name
    name.presence || email_address.split("@").first
  end
end
