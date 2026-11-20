require "test_helper"

class AccountTest < ActiveSupport::TestCase
  setup do
    @fund = accounts(:one)
    @other_fund = accounts(:two)
    @admin = users(:one)
    @member = users(:two)
  end

  test "active_users lists each member once, however many funds they are in" do
    @other_fund.add_member(@member)
    @other_fund.add_member(@admin, role: "admin")

    assert_equal [ @admin, @member ].sort_by(&:id), @fund.active_users.sort_by(&:id)
    assert_equal 2, @fund.active_members_count
  end

  test "active_users leaves out inactive memberships" do
    @fund.account_memberships.find_by!(user: @member).update!(active: false)

    assert_equal [ @admin ], @fund.active_users.to_a
  end

  test "active_users ignores an active membership in another fund" do
    @fund.account_memberships.find_by!(user: @member).update!(active: false)
    @other_fund.add_member(@member)

    assert_not_includes @fund.active_users, @member
  end

  test "admins counts a sole admin in two funds once" do
    @other_fund.add_member(@admin, role: "admin")

    assert_equal 1, @fund.admins.count
    assert_equal [ @admin ], @fund.admins.to_a
  end

  test "admins leaves out inactive admins and admins of other funds" do
    @other_fund.add_member(@member, role: "admin")
    assert_not_includes @fund.admins, @member

    @fund.account_memberships.find_by!(user: @admin).update!(active: false)
    assert_empty @fund.admins
  end

  test "destroy clears every user's pointer to the fund" do
    @member.update!(current_account: @fund)

    @fund.destroy!

    assert_nil @member.reload.current_account_id
  end

  test "the fake settings are gone" do
    assert_not_respond_to @fund, :min_deposit
    assert_not_respond_to @fund, :auto_convert
    assert_not_respond_to @fund, :notifications
  end
end
