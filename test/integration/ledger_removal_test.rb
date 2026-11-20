require "test_helper"

# The self-reported ledger is gone. Nothing may read, write or link to it.
class LedgerRemovalTest < ActionDispatch::IntegrationTest
  setup do
    users(:one).update!(current_account: accounts(:one))
    sign_in_as users(:one)
  end

  test "the schema has no ledger left" do
    connection = ActiveRecord::Base.connection

    assert_not connection.table_exists?(:transactions)
    assert_not connection.column_exists?(:account_memberships, :balance_cents)
    assert_not connection.column_exists?(:accounts, :split_method)
    assert_not connection.column_exists?(:accounts, :wallet_address)
    assert_not connection.column_exists?(:users, :wallet_address)
  end

  test "ledger routes are gone" do
    get "/transactions"
    assert_response :not_found
    get "/transactions/new"
    assert_response :not_found
    post "/transactions", params: { transaction: { amount_euros: "1000000", description: "x",
                                                   transaction_type: "deposit", token: "EURe" } }
    assert_response :not_found
  end

  test "no page links to the ledger or shows a euro figure" do
    [ dashboard_path, users_path, settings_path ].each do |path|
      get path
      assert_response :success
      assert_select "a[href*='transactions']", count: 0
      assert_no_match(/€/, response.body, "#{path} still shows a euro figure")
      assert_no_match(/Storting|Uitgave|Saldo|saldo/, response.body, "#{path} still mentions the ledger")
    end
  end

  test "forms no longer offer split method or fake settings" do
    get new_account_path
    assert_select "[name='account[split_method]']", count: 0
    assert_select "[name='account[min_deposit]']", count: 0
    assert_select "[name='account[auto_convert]']", count: 0
    assert_select "[name='account[notifications]']", count: 0

    get settings_path
    assert_select "[name='account[split_method]']", count: 0
  end

  test "the dashboard shows the fund and its member count" do
    get dashboard_path

    assert_response :success
    assert_select "h2", text: "Dashboard"
    assert_select "p", text: /2 leden/
  end
end
