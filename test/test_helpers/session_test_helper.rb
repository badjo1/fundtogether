module SessionTestHelper
  # Only sets the cookie. Current.session stays empty, as it does at the start of
  # a real request, so tests cannot pass on state the app would not have.
  def sign_in_as(user)
    @signed_in_session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = @signed_in_session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  def sign_out
    @signed_in_session&.destroy!
    @signed_in_session = nil
    Current.reset
    cookies.delete("session_id")
  end

  def log_in_with_password(user, password: "password")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  def logged_in?
    get settings_path
    return false if response.redirect? && response.location == new_session_url

    true
  end
end

module FundTestHelper
  # Confirmed, because most tests are about what happens afterwards. test/integration/email_confirmation_test.rb
  # covers the unconfirmed path with confirmed: false.
  def create_user(name, email: "#{name}@example.com", confirmed: true)
    User.create!(name: name.capitalize, email_address: email, password: "password",
                 email_confirmed_at: confirmed ? Time.current : nil)
  end

  def add_to_fund(user, account, role: "member", active: true)
    account.account_memberships.create!(user: user, role: role, active: active)
    user.update!(current_account: account)
    user
  end

  # The test env uses a null cache store, so rate limits never trigger on their
  # own. This gives that store a working counter for the duration of the block.
  def with_counting_rate_limit_store
    store = ActionController::Base.cache_store
    counts = Hash.new(0)
    store.define_singleton_method(:increment) { |key, amount = 1, **| counts[key] += amount }
    yield
  ensure
    store.singleton_class.remove_method(:increment)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
  include FundTestHelper
end
