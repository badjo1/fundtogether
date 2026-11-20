require "test_helper"

class FundAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @fund = accounts(:one)
    @other_fund = accounts(:two)
    @admin = users(:one)
    @member = users(:two)
    @admin.update!(current_account: @fund)
    @member.update!(current_account: @fund)
    @viewer = add_to_fund(create_user("viewer"), @fund, role: "viewer")
    @inactive = add_to_fund(create_user("inactive"), @fund, active: false)
    @inactive_admin = add_to_fund(create_user("oldadmin"), @fund, role: "admin", active: false)
    @outsider = create_user("outsider")
    @original_name = @fund.name
  end

  def everyone_without_admin_rights
    [ @member, @viewer, @inactive, @inactive_admin, @outsider ]
  end

  # accounts#update and #destroy
  test "nobody without an active admin membership can update a fund" do
    everyone_without_admin_rights.each do |user|
      sign_in_as user
      patch account_path(@fund), params: { account: { name: "Gekaapt" } }
      assert_response :redirect, "#{user.name} should be turned away"
      assert_equal @original_name, @fund.reload.name, "#{user.name} changed the fund"
    end
  end

  test "nobody without an active admin membership can destroy a fund" do
    everyone_without_admin_rights.each do |user|
      sign_in_as user
      assert_no_difference("Account.count", "#{user.name} destroyed the fund") do
        delete account_path(@fund)
      end
      assert_response :redirect
    end
  end

  test "non-members get the same response for an existing fund and a missing one" do
    [ @outsider, @inactive ].each do |user|
      sign_in_as user

      patch account_path(@fund), params: { account: { name: "Gekaapt" } }
      existing = [ response.status, response.location, flash[:alert] ]

      patch account_path(0), params: { account: { name: "Gekaapt" } }
      missing = [ response.status, response.location, flash[:alert] ]

      assert_equal missing, existing

      delete account_path(@fund)
      assert_equal missing, [ response.status, response.location, flash[:alert] ]

      post switch_account_path(@fund)
      assert_equal missing, [ response.status, response.location, flash[:alert] ]

      delete leave_account_path(@fund)
      assert_equal missing, [ response.status, response.location, flash[:alert] ]
    end
  end

  test "active admin can update a fund and an invalid update does not raise" do
    sign_in_as @admin

    patch account_path(@fund), params: { account: { name: "Nieuwe naam" } }
    assert_redirected_to settings_path
    assert_equal "Nieuwe naam", @fund.reload.name

    patch account_path(@fund), params: { account: { name: "" } }
    assert_redirected_to settings_path
    assert_equal "Nieuwe naam", @fund.reload.name
  end

  test "active admin destroying a fund removes it and leaves other members usable" do
    add_to_fund(@member, @other_fund)
    @member.update!(current_account: @fund)
    sign_in_as @admin

    assert_difference("Account.count", -1) do
      delete account_path(@fund)
    end
    assert_redirected_to dashboard_path

    assert_nil @admin.reload.current_account_id
    assert_nil @member.reload.current_account_id
    assert_equal 0, AccountMembership.where(account_id: @fund.id).count
    assert_equal 0, Invitation.where(account_id: @fund.id).count

    sign_in_as @member
    get dashboard_path
    assert_response :success, "member of another fund should land on that fund"
    assert_select "body", text: /#{@other_fund.name}/
  end

  # Routes that only ever returned 406 or 404
  test "routes without a working action are gone" do
    sign_in_as @admin

    get "/accounts"
    assert_response :not_found
    get "/accounts/#{@fund.id}"
    assert_response :not_found
    get "/accounts/#{@fund.id}/edit"
    assert_response :not_found
    get "/users/#{@admin.id}"
    assert_response :not_found
    post "/users/invite"
    assert_response :not_found
  end

  # switch
  test "switching is POST only and needs an active membership" do
    add_to_fund(@admin, @other_fund)
    @admin.update!(current_account: @fund)
    sign_in_as @admin

    get "/accounts/#{@other_fund.id}/switch"
    assert_response :not_found
    assert_equal @fund, @admin.reload.current_account

    post switch_account_path(@other_fund)
    assert_redirected_to dashboard_path
    assert_equal @other_fund, @admin.reload.current_account
  end

  test "a former member cannot switch back into a fund" do
    sign_in_as @inactive
    @inactive.update!(current_account: nil)

    post switch_account_path(@fund)

    assert_nil @inactive.reload.current_account_id
  end

  # leave
  test "sole admin cannot leave, even as a member of a second fund" do
    add_to_fund(@admin, @other_fund)
    @admin.update!(current_account: @fund)
    sign_in_as @admin

    assert_no_difference("AccountMembership.count") do
      delete leave_account_path(@fund)
    end
    assert_redirected_to settings_path
    assert_includes @fund.admins, @admin
  end

  test "an inactive admin does not count towards leaving" do
    sign_in_as @admin

    assert_no_difference("AccountMembership.count") do
      delete leave_account_path(@fund)
    end
    assert_redirected_to settings_path
  end

  test "admin can leave when another active admin remains" do
    add_to_fund(create_user("second"), @fund, role: "admin")
    sign_in_as @admin

    assert_difference("AccountMembership.count", -1) do
      delete leave_account_path(@fund)
    end
    assert_redirected_to dashboard_path
    assert_nil @admin.reload.current_account_id
  end

  test "viewers and members can leave" do
    [ @viewer, @member ].each do |user|
      sign_in_as user
      assert_difference("AccountMembership.count", -1) do
        delete leave_account_path(@fund)
      end
    end
  end

  # settings
  test "only admins can change settings" do
    everyone_without_admin_rights.each do |user|
      sign_in_as user
      patch settings_path, params: { account: { name: "Gekaapt", description: "x" } }
      assert_response :redirect
      assert_equal @original_name, @fund.reload.name, "#{user.name} changed the settings"
    end
  end

  test "settings page has no edit or delete controls for members and viewers" do
    [ @member, @viewer ].each do |user|
      sign_in_as user
      get settings_path
      assert_response :success
      assert_select "input[name='account[name]']", count: 0
      assert_select "form[action='#{account_path(@fund)}']", count: 0
      assert_select "form[action='#{leave_account_path(@fund)}']", count: 1
    end
  end

  test "settings page has edit and delete controls for admins" do
    sign_in_as @admin
    get settings_path
    assert_select "input[name='account[name]']", count: 1
    assert_select "form[action='#{account_path(@fund)}']", count: 1
  end

  # A pointer to a fund you no longer belong to grants nothing
  test "inactive members see nothing of the fund their pointer still names" do
    sign_in_as @inactive

    [ dashboard_path, users_path, settings_path ].each do |path|
      get path
      assert_redirected_to new_account_path, "#{path} should not open for an inactive member"
    end
  end

  test "a stale pointer falls back to a fund the user is active in" do
    add_to_fund(@inactive, @other_fund)
    @inactive.update!(current_account: @fund)
    sign_in_as @inactive

    get settings_path

    assert_response :success
    assert_select "input[value='#{@original_name}']", count: 0
    assert_select "body", text: /#{@other_fund.name}/
  end

  test "the fund menu does not list funds of an inactive membership" do
    add_to_fund(@inactive, @other_fund)
    sign_in_as @inactive

    get dashboard_path

    assert_select "a", text: /#{@original_name}/, count: 0
    assert_select "form[action='#{switch_account_path(@fund)}']", count: 0
  end

  # invitations
  test "only admins can create invitations" do
    everyone_without_admin_rights.each do |user|
      sign_in_as user
      assert_no_difference("Invitation.count", "#{user.name} created an invitation") do
        post invitations_path, params: { invitation: { email: "x@example.com" } }
      end
      assert_response :redirect
    end
  end

  test "only admins can delete invitations" do
    invitation = invitations(:pending)

    everyone_without_admin_rights.each do |user|
      sign_in_as user
      assert_no_difference("Invitation.count", "#{user.name} deleted an invitation") do
        delete invitation_path(invitation)
      end
    end
  end

  test "an admin of another fund cannot delete an invitation and learns nothing" do
    other_admin = add_to_fund(create_user("otheradmin"), @other_fund, role: "admin")
    sign_in_as other_admin

    assert_no_difference("Invitation.count") do
      delete invitation_path(invitations(:pending))
    end
    existing = [ response.location, flash[:alert] ]

    delete invitation_path(0)
    assert_equal [ response.location, flash[:alert] ], existing
  end

  test "members page shows invite controls to admins only" do
    sign_in_as @admin
    get users_path
    assert_select "form[action='#{invitations_path}']"

    [ @member, @viewer ].each do |user|
      sign_in_as user
      get users_path
      assert_response :success
      assert_select "form[action='#{invitations_path}']", count: 0
      assert_select "input[name='_method'][value='delete']", count: 1 # logout only
    end
  end

  # Fund creation
  test "creating a fund makes the creator its active admin" do
    sign_in_as @outsider

    assert_difference("Account.count", 1) do
      post accounts_path, params: { account: { name: "Vakantie", description: "Spaarpot" } }
    end
    assert_redirected_to account_invite_path(Account.order(:id).last)

    membership = @outsider.reload.current_account.account_memberships.find_by(user: @outsider)
    assert membership.admin?
    assert membership.active?
  end
end
