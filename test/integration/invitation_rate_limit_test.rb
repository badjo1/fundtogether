require "test_helper"

# M2: invitation mail carries attacker-chosen text from our domain, so it has limits per person and per fund.
class InvitationRateLimitTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user("adminz")
    @fund = Account.create!(name: "Fonds Een")
    add_to_fund(@admin, @fund, role: "admin")
    sign_in_as @admin
  end

  test "invitation create is limited: 60 tries queue at most the limit" do
    with_counting_rate_limit_store do
      assert_enqueued_emails(InvitationsController::INVITES_PER_USER) do
        60.times { |i| post invitations_path, params: { account_id: @fund.id, invitation: { email: "p#{i}@example.com" } } }
      end
    end
    assert_redirected_to root_path
    assert_match "Te veel", flash[:alert]
  end

  test "other admins of the same fund share the fund's daily limit" do
    admins = 4.times.map { |i| create_user("beheerder#{i}").tap { |user| add_to_fund(user, @fund, role: "admin") } }
    created = 0
    with_counting_rate_limit_store do
      admins.each do |admin|
        sign_out
        sign_in_as admin
        InvitationsController::INVITES_PER_USER.times do |i|
          post invitations_path, params: { account_id: @fund.id, invitation: { email: "#{admin.id}-#{i}@example.com" } }
          created += 1 if response.location&.include?("success")
        end
      end
    end
    assert_equal InvitationsController::INVITES_PER_FUND, created
  end
end
