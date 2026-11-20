require "test_helper"

# H3: links in mail come from configuration. Host and X-Forwarded-Host are attacker input.
class MailLinkHostTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user("adminz")
    @fund = Account.create!(name: "Fonds Een")
    add_to_fund(@admin, @fund, role: "admin")
    ActionMailer::Base.deliveries.clear
    sign_in_as @admin
  end

  def assert_only_configured_host(text)
    assert_match "https://fundtogether.test/", text
    assert_no_match(/evil/, text)
  end

  test "invitation mail ignores the Host header" do
    perform_enqueued_jobs do
      post invitations_path, params: { account_id: @fund.id, invitation: { email: "bas@example.com" } }, headers: { "Host" => "evil.test" }
    end
    assert_only_configured_host ActionMailer::Base.deliveries.last.text_part.body.to_s
  end

  test "invitation mail ignores X-Forwarded-Host" do
    perform_enqueued_jobs do
      post invitations_path, params: { account_id: @fund.id, invitation: { email: "bas@example.com" } },
                             headers: { "X-Forwarded-Host" => "evil2.test" }
    end
    assert_only_configured_host ActionMailer::Base.deliveries.last.text_part.body.to_s
  end

  test "send_email and the share page ignore the Host header" do
    invitation = @fund.invitations.create!(invited_by: @admin)
    evil = { "Host" => "evil.test" }
    perform_enqueued_jobs do
      post send_email_invitation_path(invitation.token), params: { email: "bas@example.com" }, headers: evil
    end
    assert_only_configured_host ActionMailer::Base.deliveries.last.text_part.body.to_s

    post invitations_path, params: { account_id: @fund.id, invitation: { email: "cor@example.com" } }, headers: evil
    get invitation_success_path, headers: evil
    assert_match "https://fundtogether.test/invitations/", response.body
    assert_no_match %r{https?://evil\.test/invitations}, response.body
  end

  test "password reset and verification mail ignore the Host header" do
    host! "evil.test"
    perform_enqueued_jobs { post passwords_path, params: { email_address: @admin.email_address } }
    assert_only_configured_host ActionMailer::Base.deliveries.last.text_part.body.to_s

    invitation = @fund.invitations.create!(invited_by: @admin)
    perform_enqueued_jobs do
      post request_email_verification_invitation_path(invitation.token), params: { email: "bas@example.com" }
    end
    assert_only_configured_host ActionMailer::Base.deliveries.last.text_part.body.to_s
  end

  test "production host list comes from APP_HOST, with www and extras, and /up is excluded" do
    assert_equal [ "fundtogether.example", "www.fundtogether.example" ], ProductionHosts.allowed("APP_HOST" => "fundtogether.example")
    assert_equal [ "a.example", "www.a.example", "b.example" ], ProductionHosts.allowed("APP_HOST" => "a.example", "ALLOWED_HOSTS" => "b.example,")
    assert_raises(KeyError) { ProductionHosts.allowed({}) }

    app = ActionDispatch::HostAuthorization.new(->(_env) { [ 200, {}, [ "ok" ] ] }, ProductionHosts.allowed("APP_HOST" => "fundtogether.example"), exclude: ProductionHosts::EXCLUDE)
    status = ->(path, env = {}) { app.call(Rack::MockRequest.env_for(path, env)).first }
    assert_equal 200, status.call("/", "HTTP_HOST" => "fundtogether.example")
    assert_equal 403, status.call("/", "HTTP_HOST" => "evil.test")
    assert_equal 403, status.call("/", "HTTP_HOST" => "fundtogether.example", "HTTP_X_FORWARDED_HOST" => "evil.test")
    assert_equal 200, status.call("/up", "HTTP_HOST" => "10.0.0.5")
  end
end
