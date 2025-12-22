require "test_helper"

class InvitationMailerTest < ActionMailer::TestCase
  def setup
    @account = accounts(:one)
    @inviter = users(:one)
    @invitation = Invitation.create!(
      account: @account,
      invited_by: @inviter,
      email: "test@example.com"
    )
    @invitation_url = "http://example.com/invitations/#{@invitation.token}/open"
  end

  # Test invite email (direct email flow)
  test "invite email contains correct subject" do
    email = InvitationMailer.invite(@invitation, @invitation_url)

    assert_equal "#{@inviter.name} heeft je uitgenodigd voor #{@account.name}", email.subject
    assert_equal [ "test@example.com" ], email.to
  end

  test "invite email contains invitation link" do
    email = InvitationMailer.invite(@invitation, @invitation_url)

    text_part = email.parts.find { |p| p.content_type.start_with?("text/plain") }
    assert_match "/invitations/", text_part.decoded
    assert_match "/open", text_part.decoded
  end

  test "invite email contains account name" do
    email = InvitationMailer.invite(@invitation, @invitation_url)

    assert_match @account.name, email.body.encoded
  end

  test "invite email contains inviter name" do
    email = InvitationMailer.invite(@invitation, @invitation_url)

    assert_match @inviter.name, email.body.encoded
  end

  # Test verify_email email (WhatsApp/QR/Link flow)
  test "verify_email email contains correct subject" do
    @invitation.generate_email_verification_token
    @invitation.save

    email = InvitationMailer.verify_email(@invitation)

    assert_equal "Bevestig je email voor #{@account.name}", email.subject
    assert_equal [ "test@example.com" ], email.to
  end

  test "verify_email email contains verification link" do
    @invitation.generate_email_verification_token
    @invitation.save

    email = InvitationMailer.verify_email(@invitation)

    text_part = email.parts.find { |p| p.content_type.start_with?("text/plain") }
    assert_match "/invitations/", text_part.decoded
    assert_match "/verify/", text_part.decoded
  end

  test "verify_email email contains account name" do
    @invitation.generate_email_verification_token
    @invitation.save

    email = InvitationMailer.verify_email(@invitation)

    assert_match @account.name, email.body.encoded
  end

  # Test both emails have HTML and text parts
  test "invite email has both HTML and text parts" do
    email = InvitationMailer.invite(@invitation, @invitation_url)

    assert_equal 2, email.parts.size
    assert_equal "text/plain", email.parts[0].content_type.split(";").first
    assert_equal "text/html", email.parts[1].content_type.split(";").first
  end

  test "verify_email email has both HTML and text parts" do
    @invitation.generate_email_verification_token
    @invitation.save

    email = InvitationMailer.verify_email(@invitation)

    assert_equal 2, email.parts.size
    assert_equal "text/plain", email.parts[0].content_type.split(";").first
    assert_equal "text/html", email.parts[1].content_type.split(";").first
  end

  # Test that emails are sent from the correct sender
  test "invite email has correct from address" do
    email = InvitationMailer.invite(@invitation, @invitation_url)

    assert_equal [ "noreply@fundtogether.app" ], email.from
  end

  test "verify_email email has correct from address" do
    @invitation.generate_email_verification_token
    @invitation.save

    email = InvitationMailer.verify_email(@invitation)

    assert_equal [ "noreply@fundtogether.app" ], email.from
  end
end
