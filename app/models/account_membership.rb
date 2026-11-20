class AccountMembership < ApplicationRecord
  belongs_to :account
  belongs_to :user

  # Validations
  validates :role, presence: true, inclusion: { in: %w[admin member viewer] }
  validates :user_id, uniqueness: { scope: :account_id, message: "is already in this account" }

  # Enums
  enum :role, { admin: "admin", member: "member", viewer: "viewer" }

  # Callbacks
  before_validation :set_defaults, on: :create

  # Scopes
  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: "admin") }

  private

  def set_defaults
    self.role ||= "member"
    self.active = true if active.nil?
    self.joined_at ||= Time.current
  end
end
