require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:one)
    @user = users(:two)
    @pending_invitation = invitations(:pending)
    @expired_invitation = invitations(:expired)
    @accepted_invitation = invitations(:accepted)
  end

  # Validations
  test "should be valid with valid attributes" do
    invitation = Invitation.new(
      account: @account,
      invited_by: @user,
      email: "test@example.com",
      status: "pending",
      token: SecureRandom.hex(32)
    )
    assert invitation.valid?
  end

  test "should allow creation without email for WhatsApp/QR/Link flows" do
    invitation = Invitation.new(
      account: @account,
      invited_by: @user,
      status: "pending"
    )
    assert invitation.valid?, "Invitation should be valid without email"
  end

  test "should require valid email format" do
    invitation = Invitation.new(
      account: @account,
      email: "invalid-email",
      status: "pending"
    )
    assert_not invitation.valid?
    assert_includes invitation.errors[:email], "is invalid"
  end

  test "should require status" do
    invitation = Invitation.new(account: @account, email: "test@example.com")
    invitation.status = nil
    assert_not invitation.valid?
  end

  test "should require token" do
    invitation = Invitation.new(
      account: @account,
      email: "test@example.com",
      status: "pending"
    )
    invitation.token = nil
    assert_not invitation.valid?
  end

  test "should generate token before validation on create" do
    invitation = Invitation.new(
      account: @account,
      invited_by: @user,
      email: "test@example.com"
    )
    assert_nil invitation.token
    invitation.valid?
    assert_not_nil invitation.token
  end

  test "should set status to pending by default" do
    invitation = Invitation.new(
      account: @account,
      invited_by: @user,
      email: "test@example.com"
    )
    assert_nil invitation.status
    invitation.valid?
    assert_equal "pending", invitation.status
  end

  test "should not override explicitly set status" do
    invitation = Invitation.new(
      account: @account,
      invited_by: @user,
      email: "test@example.com",
      status: "accepted"
    )
    invitation.valid?
    assert_equal "accepted", invitation.status
  end

  test "should require unique token" do
    invitation1 = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "test1@example.com",
      status: "pending"
    )

    invitation2 = Invitation.new(
      account: @account,
      invited_by: @user,
      email: "test2@example.com",
      status: "pending",
      token: invitation1.token
    )
    assert_not invitation2.valid?
    assert_includes invitation2.errors[:token], "has already been taken"
  end

  # Scopes
  test "pending scope should return only pending invitations" do
    pending_invitations = Invitation.pending
    assert_includes pending_invitations, @pending_invitation
    assert_not_includes pending_invitations, @accepted_invitation
    assert_not_includes pending_invitations, invitations(:rejected)
  end

  test "expired scope should return invitations older than 24 hours" do
    expired_invitations = Invitation.expired
    assert_includes expired_invitations, @expired_invitation
    assert_not_includes expired_invitations, @pending_invitation
  end

  test "active scope should return non-expired pending invitations" do
    active_invitations = Invitation.active
    assert_includes active_invitations, @pending_invitation
    assert_not_includes active_invitations, @expired_invitation
    assert_not_includes active_invitations, @accepted_invitation
  end

  # Instance Methods
  test "expired? should return true for invitations older than 24 hours" do
    assert @expired_invitation.expired?
    assert_not @pending_invitation.expired?
  end

  test "expired? should return false for non-pending invitations" do
    assert_not @accepted_invitation.expired?
  end

  test "expires_at should return created_at plus 24 hours" do
    expected_expiry = @pending_invitation.created_at + 24.hours
    assert_equal expected_expiry.to_i, @pending_invitation.expires_at.to_i
  end

  test "time_remaining should return seconds until expiry" do
    remaining = @pending_invitation.time_remaining
    assert remaining > 0
    assert remaining <= 24.hours
  end

  test "time_remaining should return 0 for expired invitations" do
    assert_equal 0, @expired_invitation.time_remaining
  end

  # Accept Method
  test "accept! should add user to account as member" do
    # Use a user that is not already in the account
    new_user = User.create!(name: "New User", email_address: "newuser@test.com", password: "password")

    # Verify email before accepting
    @pending_invitation.verify_email!

    assert_difference "@account.users.count", 1 do
      @pending_invitation.accept!(new_user)
    end

    @account.reload
    membership = @account.account_memberships.find_by(user: new_user)
    assert_not_nil membership
    assert_equal "member", membership.role
    assert membership.active?
  end

  test "accept! should update status to accepted" do
    new_user = User.create!(name: "New User 2", email_address: "newuser2@test.com", password: "password")

    # Verify email before accepting
    @pending_invitation.verify_email!

    @pending_invitation.accept!(new_user)
    assert @pending_invitation.reload.accepted?
  end

  test "accept! should return false for expired invitations" do
    new_user = User.create!(name: "New User 3", email_address: "newuser3@test.com", password: "password")
    result = @expired_invitation.accept!(new_user)
    assert_equal false, result
  end

  # Reject Method
  test "reject! should update status to rejected" do
    @pending_invitation.reject!
    assert @pending_invitation.reload.rejected?
  end

  # Enum
  test "should have correct status enum values" do
    invitation = Invitation.new(account: @account, invited_by: @user, email: "test@example.com")

    invitation.status = :pending
    assert invitation.pending?

    invitation.status = :accepted
    assert invitation.accepted?

    invitation.status = :rejected
    assert invitation.rejected?
  end

  # Re-invitation Rules
  test "should allow re-invitation after rejection" do
    # First invitation is rejected
    first_invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "rejected@example.com",
      status: "rejected"
    )

    # Should be able to create a new invitation for the same email
    second_invitation = Invitation.new(
      account: @account,
      invited_by: @user,
      email: "rejected@example.com"
    )

    assert second_invitation.valid?, "Should allow re-invitation after rejection"
  end

  test "should not allow re-invitation after acceptance" do
    # First invitation is accepted
    first_invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "accepted@example.com",
      status: "accepted"
    )

    # Should not be able to create a new invitation for the same email
    second_invitation = Invitation.new(
      account: @account,
      invited_by: @user,
      email: "accepted@example.com"
    )

    assert_not second_invitation.valid?, "Should not allow re-invitation after acceptance"
    assert_includes second_invitation.errors[:email], "is already accepted for this account"
  end

  test "should allow invitation for same email in different account" do
    other_account = accounts(:two)

    # First invitation is accepted in account one
    first_invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "multiacccount@example.com",
      status: "accepted"
    )

    # Should be able to create invitation for same email in different account
    second_invitation = Invitation.new(
      account: other_account,
      invited_by: @user,
      email: "multiacccount@example.com"
    )

    assert second_invitation.valid?, "Should allow invitation for same email in different account"
  end

  # Security: Access Control
  test "should only grant access to invited account, not other accounts" do
    other_account = accounts(:two)
    new_user = User.create!(
      name: "Invited User",
      email_address: "invited@example.com",
      password: "password"
    )

    # Create invitation for account one only
    invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "invited@example.com"
    )

    # Verify email before accepting
    invitation.verify_email!

    # Accept invitation
    invitation.accept!(new_user)

    # User should be member of invited account
    assert_includes @account.users, new_user, "User should be member of invited account"
    assert @account.account_memberships.find_by(user: new_user).present?, "Membership should exist for invited account"

    # User should NOT be member of other account
    assert_not_includes other_account.users, new_user, "User should NOT be member of other account"
    assert_nil other_account.account_memberships.find_by(user: new_user), "No membership should exist for other account"

    # Verify user has correct role in invited account
    membership = @account.account_memberships.find_by(user: new_user)
    assert_equal "member", membership.role, "User should have 'member' role"
    assert membership.active?, "Membership should be active"
  end

  test "accepting invitation for account A should not grant access to account B" do
    account_a = @account
    account_b = accounts(:two)
    new_user = User.create!(
      name: "Security Test User",
      email_address: "security@example.com",
      password: "password"
    )

    # Create invitations for BOTH accounts (but user only accepts one)
    invitation_a = Invitation.create!(
      account: account_a,
      invited_by: @user,
      email: "security@example.com"
    )

    invitation_b = Invitation.create!(
      account: account_b,
      invited_by: @user,
      email: "security@example.com"
    )

    # Verify email for invitation A only
    invitation_a.verify_email!

    # User only accepts invitation for account A
    invitation_a.accept!(new_user)

    # Verify access
    assert_includes account_a.users, new_user, "User should have access to account A"
    assert_not_includes account_b.users, new_user, "User should NOT have access to account B"

    # Verify invitation statuses
    assert invitation_a.reload.accepted?, "Invitation A should be accepted"
    assert invitation_b.reload.pending?, "Invitation B should still be pending"
  end

  # Re-invitation: Cancel Previous Pending
  test "should cancel previous pending invitation when re-inviting same email" do
    # First invitation is pending
    first_invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "reinvite@example.com"
    )

    assert first_invitation.pending?, "First invitation should be pending"
    first_invitation_id = first_invitation.id

    # Create second invitation for same email and account
    second_invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "reinvite@example.com"
    )

    # First invitation should be cancelled/deleted
    assert_nil Invitation.find_by(id: first_invitation_id), "First invitation should be deleted"

    # Second invitation should be active
    assert second_invitation.pending?, "Second invitation should be pending"
    assert_equal "reinvite@example.com", second_invitation.email

    # Only one active invitation should exist for this email + account combo
    active_count = Invitation.where(
      account: @account,
      email: "reinvite@example.com",
      status: "pending"
    ).count
    assert_equal 1, active_count, "Should only have one pending invitation"
  end

  test "should not cancel pending invitation in different account when re-inviting" do
    other_account = accounts(:two)

    # Create pending invitation in account one
    invitation_account_one = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "multi@example.com"
    )

    # Create invitation for same email in account two
    invitation_account_two = Invitation.create!(
      account: other_account,
      invited_by: @user,
      email: "multi@example.com"
    )

    # Both invitations should still be pending
    assert invitation_account_one.reload.pending?, "Invitation in account one should still be pending"
    assert invitation_account_two.pending?, "Invitation in account two should be pending"

    # Each account should have one pending invitation
    assert_equal 1, @account.invitations.pending.where(email: "multi@example.com").count
    assert_equal 1, other_account.invitations.pending.where(email: "multi@example.com").count
  end

  # Email Verification Tests
  test "should allow invitation creation without email" do
    invitation = Invitation.new(
      account: @account,
      invited_by: @user,
      status: "pending"
    )
    assert invitation.valid?, "Invitation should be valid without email"
  end

  test "awaiting_email? should return true when email is blank" do
    invitation = Invitation.create!(
      account: @account,
      invited_by: @user
    )
    assert invitation.awaiting_email?, "Should be awaiting email when email is blank"
  end

  test "email_verified? should return false by default" do
    invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "test@example.com"
    )
    assert_not invitation.email_verified?, "Email should not be verified by default"
  end

  test "verify_email! should set email_verified_at" do
    invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "test@example.com"
    )

    assert_nil invitation.email_verified_at
    invitation.verify_email!

    invitation.reload
    assert_not_nil invitation.email_verified_at
    assert invitation.email_verified?
  end

  test "generate_email_verification_token should create signed token" do
    invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "test@example.com"
    )

    invitation.generate_email_verification_token

    assert_not_nil invitation.email_verification_token
    assert_not_nil invitation.email_verification_sent_at
  end

  test "find_by_email_verification_token should find invitation with valid token" do
    invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "test@example.com"
    )

    invitation.generate_email_verification_token
    invitation.save

    found = Invitation.find_by_email_verification_token(invitation.email_verification_token)
    assert_equal invitation, found
  end

  test "find_by_email_verification_token should return nil for invalid token" do
    found = Invitation.find_by_email_verification_token("invalid_token")
    assert_nil found
  end

  test "ready_to_accept? should require email, verified, pending, and not expired" do
    invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "test@example.com"
    )

    # Not verified yet
    assert_not invitation.ready_to_accept?, "Should not be ready without verification"

    # Verify email
    invitation.verify_email!
    assert invitation.ready_to_accept?, "Should be ready after verification"

    # Accept invitation
    new_user = User.create!(name: "Test", email_address: "test@example.com", password: "password")
    invitation.accept!(new_user)
    assert_not invitation.ready_to_accept?, "Should not be ready after acceptance"
  end

  test "accept! should fail if not ready_to_accept?" do
    invitation = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "unverified@example.com"
    )

    new_user = User.create!(name: "Test User", email_address: "unverified@example.com", password: "password")
    result = invitation.accept!(new_user)

    assert_equal false, result, "Accept should fail for unverified email"
    assert invitation.pending?, "Invitation should still be pending"
  end

  test "email_verified and awaiting_email scopes should work correctly" do
    # Create verified invitation
    verified = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "verified@example.com"
    )
    verified.verify_email!

    # Create unverified invitation with email
    unverified = Invitation.create!(
      account: @account,
      invited_by: @user,
      email: "unverified@example.com"
    )

    # Create invitation without email
    no_email = Invitation.create!(
      account: @account,
      invited_by: @user
    )

    # Test scopes
    assert_includes Invitation.email_verified, verified
    assert_not_includes Invitation.email_verified, unverified

    assert_includes Invitation.awaiting_email, no_email
    assert_not_includes Invitation.awaiting_email, verified
  end
end
