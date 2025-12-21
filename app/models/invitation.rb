# app/models/invitation.rb
class Invitation < ApplicationRecord
  belongs_to :account
  belongs_to :invited_by, class_name: 'User'

  # Email alleen required als verified (niet bij creatie - voor WhatsApp/QR/Link flows)
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :status, presence: true,
            inclusion: { in: %w[pending accepted rejected] }
  validates :token, presence: true, uniqueness: true
  validate :email_not_already_accepted, on: :create, if: -> { email.present? }
  validate :email_required_before_accept, if: -> { accepting? }

  enum :status, { pending: 'pending', accepted: 'accepted', rejected: 'rejected' }

  before_validation :set_defaults, on: :create
  before_create :cancel_previous_pending_invitations

  scope :pending, -> { where(status: 'pending') }
  scope :expired, -> { where('created_at < ?', 24.hours.ago).where(status: 'pending') }
  scope :active, -> { where(status: 'pending').where('created_at >= ?', 24.hours.ago) }
  scope :email_verified, -> { where.not(email_verified_at: nil) }
  scope :awaiting_email, -> { where(email: nil) }

  # Email verificatie methods
  def email_verified?
    email_verified_at.present?
  end

  def awaiting_email?
    email.blank?
  end

  def ready_to_accept?
    email.present? && email_verified? && pending? && !expired?
  end

  def generate_email_verification_token
    self.email_verification_token = signed_token_for(:email_verification)
    self.email_verification_sent_at = Time.current
  end

  def verify_email!
    update!(email_verified_at: Time.current)
  end

  def self.find_by_email_verification_token(token)
    verifier = Rails.application.message_verifier(:email_verification)
    invitation_id = verifier.verify(token, purpose: :email_verification)
    find_by(id: invitation_id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def accept!(user)
    return false if expired?
    return false unless ready_to_accept?

    account.add_member(user, role: 'member')
    update!(status: 'accepted')
    user
  end

  def reject!
    update!(status: 'rejected')
  end

  def expired?
    created_at < 24.hours.ago && pending?
  end

  def expires_at
    created_at + 24.hours
  end

  def time_remaining
    return 0 if invitation_expired?
    remaining = (expires_at - Time.current).to_i
    [remaining, 0].max
  end

  def invitation_expired?
    created_at < 24.hours.ago && pending?
  end

  # Alias for backwards compatibility
  alias_method :expired?, :invitation_expired?
  
  private

  def signed_token_for(purpose)
    verifier = Rails.application.message_verifier(purpose)
    verifier.generate(id, purpose: purpose, expires_in: 2.hours)
  end

  def set_defaults
    self.status ||= 'pending'
    self.token ||= SecureRandom.hex(32)
  end

  def email_not_already_accepted
    return unless email.present? && account.present?

    existing_accepted = Invitation.where(
      account: account,
      email: email,
      status: 'accepted'
    ).where.not(id: id).exists?

    if existing_accepted
      errors.add(:email, "is already accepted for this account")
    end
  end

  def email_required_before_accept
    if status == 'accepted' && email.blank?
      errors.add(:email, "must be present before accepting")
    end
  end

  def accepting?
    status_changed? && status == 'accepted'
  end

  def cancel_previous_pending_invitations
    return unless email.present? && account.present?

    # Delete all previous pending invitations for this email + account combination
    Invitation.where(
      account: account,
      email: email,
      status: 'pending'
    ).where.not(id: id).destroy_all
  end
end