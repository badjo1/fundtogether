# app/models/invitation.rb
class Invitation < ApplicationRecord
  belongs_to :account
  belongs_to :invited_by, class_name: "User"

  normalizes :email, with: ->(e) { e.strip.downcase.presence }
  normalizes :invitee_name, with: ->(value) { SafeText.clean(value) }

  # Email alleen required als verified (niet bij creatie - voor WhatsApp/QR/Link flows)
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :status, presence: true,
            inclusion: { in: %w[pending accepted rejected] }
  validates :token, presence: true, uniqueness: true
  validate :email_not_already_accepted, on: :create, if: -> { email.present? }
  validate :email_required_before_accept, if: -> { accepting? }

  enum :status, { pending: "pending", accepted: "accepted", rejected: "rejected" }

  before_validation :set_defaults, on: :create
  before_create :cancel_previous_pending_invitations

  scope :pending, -> { where(status: "pending") }
  scope :expired, -> { where("created_at < ?", 24.hours.ago).where(status: "pending") }
  scope :active, -> { where(status: "pending").where("created_at >= ?", 24.hours.ago) }
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

  # A token only verifies the address it was mailed to, and only the latest one counts.
  def generate_email_verification_token
    self.email_verification_token = signed_verification_token
    self.email_verification_sent_at = Time.current
  end

  def verify_email!
    update!(email_verified_at: Time.current)
  end

  def self.find_by_email_verification_token(token)
    payload = Rails.application.message_verifier(:email_verification).verify(token, purpose: :email_verification)
    invitation = find_by(id: payload["id"])
    return unless invitation&.email.present? && invitation.email == payload["email"]
    return unless ActiveSupport::SecurityUtils.secure_compare(invitation.email_verification_token.to_s, token)

    invitation
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  # Link holder names their address and has to prove it by mail. Refused once verified.
  def claim_email(address)
    return false if email_verified?

    self.email = address
    return false if email.blank?

    generate_email_verification_token
    save
  end

  # An admin names the addressee directly; only that address can then accept.
  def address_to(address)
    self.email = address
    return false if email.blank?

    self.email_verified_at = Time.current
    self.email_verification_token = nil
    save
  end

  def email_matches?(user)
    email.present? && email.casecmp?(user.email_address)
  end

  def accept!(user)
    with_lock do
      next false unless ready_to_accept? && email_matches?(user) && user.email_confirmed?

      membership = account.account_memberships.find_by(user: user)
      if membership.nil?
        account.add_member(user, role: "member")
      elsif !membership.active?
        membership.update!(active: true, role: "member")
      end

      update!(status: "accepted")
      user
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    false
  end

  # An unclaimed link can be declined by whoever holds it. Once an address is verified,
  # only that person or an admin of the fund can, so a forwarded link cannot cancel it.
  def rejectable_by?(user)
    return true unless email_verified?

    user.present? && (email_matches?(user) || account.active_admin?(user))
  end

  def reject!
    update!(status: "rejected")
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
    [ remaining, 0 ].max
  end

  def invitation_expired?
    created_at < 24.hours.ago && pending?
  end

  # Alias for backwards compatibility
  alias_method :expired?, :invitation_expired?

  private

  def signed_verification_token
    Rails.application.message_verifier(:email_verification).generate(
      { "id" => id, "email" => email },
      purpose: :email_verification,
      expires_in: 2.hours
    )
  end

  def set_defaults
    self.status ||= "pending"
    self.token ||= SecureRandom.hex(32)
  end

  def email_not_already_accepted
    return unless email.present? && account.present?

    existing_accepted = Invitation.where(
      account: account,
      email: email,
      status: "accepted"
    ).where.not(id: id).exists?

    if existing_accepted
      errors.add(:email, "is already accepted for this account")
    end
  end

  def email_required_before_accept
    if status == "accepted" && email.blank?
      errors.add(:email, "must be present before accepting")
    end
  end

  def accepting?
    status_changed? && status == "accepted"
  end

  def cancel_previous_pending_invitations
    return unless email.present? && account.present?

    # Delete all previous pending invitations for this email + account combination
    Invitation.where(
      account: account,
      email: email,
      status: "pending"
    ).where.not(id: id).destroy_all
  end
end
