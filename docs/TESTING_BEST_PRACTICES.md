# Testing Best Practices

## Wat we vandaag geleerd hebben

### Het Probleem
De `send_invitation_email` actie checkte `@invitation.email` in plaats van de email uit het formulier (`params[:email]`). Dit type bug ontstaat wanneer:
- Controller acties data verwachten op de verkeerde plek
- Forms data sturen die niet correct verwerkt wordt
- Geen tests zijn voor de complete user flow

### De Fix
```ruby
# ❌ Fout - checkt bestaande data
if @invitation.email.present?
  # ...
end

# ✅ Correct - haalt data uit params
email = params[:email]
if email.present?
  @invitation.update!(email: email)
  # ...
end
```

## Hoe Dit Te Voorkomen

### 1. Test-Driven Development (TDD)
**Schrijf tests VOORDAT je de feature implementeert:**

```ruby
# Schrijf eerst de test
test "should update invitation email when sending from success page" do
  invitation = Invitation.create!(account: @account, invited_by: @user)

  post send_email_invitation_path(invitation.token), params: {
    email: "new@example.com"
  }

  invitation.reload
  assert_equal "new@example.com", invitation.email
end

# Dan implementeer je de feature
# De test faalt eerst, dan maak je hem groen
```

### 2. Test Alle User Flows
Voor elke nieuwe feature, test minimaal:

#### Controller Tests
- ✅ Happy path (alles werkt)
- ✅ Edge cases (lege data, invalide data)
- ✅ Error handling (wat als het misgaat?)

#### Integration Tests
- ✅ Complete user journey van begin tot eind
- ✅ Multiple scenarios (ingelogd/uitgelogd, nieuwe/bestaande user)

### 3. Code Review Checklist

Bij elke nieuwe controller actie, check:

```ruby
# 1. Worden params correct gelezen?
params[:email]           # ✅ Direct uit params
params.require(:user)    # ✅ Met strong parameters
@model.email            # ⚠️  Komt dit uit een form of database?

# 2. Worden models correct geüpdatet?
@model.update!(params)   # ✅ Update met nieuwe data
if @model.email.present? # ⚠️  Check: is dit oude of nieuwe data?

# 3. Is er error handling?
if email.present?
  # success
else
  # error - wat gebeurt er?
end
```

### 4. Test Patronen Voor Forms

Altijd testen:

```ruby
# Pattern 1: Form stuurt data → Controller verwerkt → Model update
test "should process form data" do
  post action_path, params: { field: "value" }

  model.reload
  assert_equal "value", model.field  # ✅ Check data is opgeslagen
  assert_redirected_to success_path  # ✅ Check redirect
  assert_match /success/i, flash[:notice]  # ✅ Check feedback
end

# Pattern 2: Form stuurt lege data → Error handling
test "should handle empty form data" do
  post action_path, params: { field: "" }

  assert_redirected_to error_path
  assert_match /error/i, flash[:alert]
end

# Pattern 3: Form stuurt invalide data → Validation
test "should validate form data" do
  post action_path, params: { email: "invalid" }

  assert_response :unprocessable_entity
  # of
  assert_match /invalid/i, flash[:alert]
end
```

### 5. Test Coverage Monitoring

Gebruik SimpleCov om test coverage te checken:

```ruby
# In test_helper.rb
require 'simplecov'
SimpleCov.start 'rails' do
  add_filter '/test/'
  add_filter '/config/'

  add_group 'Controllers', 'app/controllers'
  add_group 'Models', 'app/models'
  add_group 'Mailers', 'app/mailers'
end
```

Streef naar:
- **Controllers:** 90%+ coverage
- **Models:** 95%+ coverage
- **Critical paths:** 100% coverage

### 6. Automated Testing in CI/CD

Zorg dat tests automatisch draaien:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: bundle exec rails test
      - name: Upload coverage
        uses: codecov/codecov-action@v2
```

## Concrete Acties Voor Dit Project

### Onmiddellijk
- [x] Tests toegevoegd voor nieuwe invitation flow
- [x] Bug gefixed in `send_invitation_email`
- [x] Controller tests uitgebreid (nu 24 tests)

### Volgende Stappen
1. **Integration test toevoegen** voor complete button → email flow
2. **System test** met browser automation (Capybara)
3. **API tests** als jullie een API hebben

### Test Template Voor Nieuwe Features

```ruby
# test/controllers/new_feature_controller_test.rb
require "test_helper"

class NewFeatureControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = accounts(:one)
    sign_in_as(@user)
  end

  # Happy path
  test "should do the thing successfully" do
    post new_feature_path, params: { data: "value" }

    assert_response :success
    assert_equal "value", Model.last.data
    assert flash[:notice].present?
  end

  # Edge case: empty data
  test "should handle empty data gracefully" do
    post new_feature_path, params: { data: "" }

    assert_response :redirect
    assert flash[:alert].present?
  end

  # Edge case: invalid data
  test "should validate data format" do
    post new_feature_path, params: { data: "invalid" }

    assert_response :unprocessable_entity
  end

  # Authorization
  test "should require authentication" do
    sign_out
    post new_feature_path

    assert_redirected_to login_path
  end
end
```

## Resources

- **Rails Testing Guide:** https://guides.rubyonrails.org/testing.html
- **Minitest Documentation:** https://github.com/minitest/minitest
- **Better Specs:** https://www.betterspecs.org/
- **Test-Driven Rails:** https://thoughtbot.com/blog/how-we-test-rails-applications

## Vragen?

Als je twijfelt of een feature genoeg getest is, vraag jezelf af:
1. Wat kan er misgaan?
2. Heb ik dat getest?
3. Zou een nieuwe developer dit begrijpen?

**Als het antwoord "nee" is → schrijf een test!**
