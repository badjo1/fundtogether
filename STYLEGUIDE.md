# FundTogether Styleguide

> Code styling, conventions, en best practices voor het FundTogether project

**Versie:** 1.0
**Laatste update:** 2025-12-20

---

## Inhoudsopgave

1. [Project Overzicht](#project-overzicht)
2. [Code Formatting](#code-formatting)
3. [Naming Conventions](#naming-conventions)
4. [File Structure](#file-structure)
5. [Views & Templates](#views--templates)
6. [Components & Partials](#components--partials)
7. [CSS & Styling (Tailwind)](#css--styling-tailwind)
8. [JavaScript & Stimulus](#javascript--stimulus)
9. [Rails Conventions](#rails-conventions)
10. [Database & Models](#database--models)
11. [Testing](#testing)
12. [Security](#security)
13. [Git Workflow](#git-workflow)

---

## Project Overzicht

**FundTogether** is een Rails 8 applicatie voor gedeelde fondsen met blockchain integratie.

**Tech Stack:**
- Ruby 3.4.6
- Rails 8.1.1
- PostgreSQL
- Hotwire (Turbo + Stimulus)
- Tailwind CSS 4.4
- Web3/Ethereum (MetaMask)

**Deployment:**
- Puma + Thruster
- Docker support
- GitHub Actions CI/CD

---

## Code Formatting

### Ruby

**Indentatie:** 2 spaties (geen tabs)

```ruby
# ✅ Goed
def calculate_balance
  if account.present?
    account.balance_cents / 100.0
  else
    0.0
  end
end

# ❌ Fout (4 spaties of tabs)
def calculate_balance
    if account.present?
        account.balance_cents / 100.0
    end
end
```

**Lijn lengte:** Max 120 karakters

**String quotes:**
- Gebruik single quotes voor strings zonder interpolation
- Gebruik double quotes voor interpolation

```ruby
# ✅ Goed
name = 'John Doe'
message = "Welkom, #{name}!"

# ❌ Fout
name = "John Doe"
message = 'Welkom, ' + name + '!'
```

### ERB Templates

**Indentatie:** 2 spaties

```erb
<!-- ✅ Goed -->
<div class="container">
  <% if user.present? %>
    <h1><%= user.name %></h1>
  <% end %>
</div>

<!-- ❌ Fout -->
<div class="container">
<% if user.present? %>
<h1><%= user.name %></h1>
<% end %>
</div>
```

**ERB tags:**
- `<%= %>` voor output
- `<% %>` voor logic (geen output)
- `<%# %>` voor comments

---

## Naming Conventions

### Files & Directories

**Models:** Singular, snake_case
```
app/models/user.rb
app/models/account_membership.rb
```

**Controllers:** Plural, snake_case
```
app/controllers/users_controller.rb
app/controllers/account_memberships_controller.rb
```

**Views:** Match controller name, snake_case
```
app/views/users/index.html.erb
app/views/users/show.html.erb
```

**Partials:** Prefix met underscore
```
app/views/shared/_sidebar.html.erb
app/views/users/_form.html.erb
```

### Ruby Code

**Classes & Modules:** PascalCase
```ruby
class AccountMembership
module Authentication
```

**Methods & Variables:** snake_case
```ruby
def calculate_balance
  user_balance = 0
end
```

**Constants:** SCREAMING_SNAKE_CASE
```ruby
MAX_UPLOAD_SIZE = 10.megabytes
DEFAULT_CURRENCY = 'EUR'
```

**Boolean methods:** End with `?`
```ruby
def admin?
  role == 'admin'
end

def active_in_account?(account)
  # ...
end
```

**Destructive methods:** End with `!`
```ruby
def increment_balance!(amount)
  # modifies object
end
```

### Database

**Tables:** Plural, snake_case
```sql
users
accounts
account_memberships
```

**Columns:** snake_case
```sql
email_address
created_at
balance_cents
```

**Foreign keys:** `{model}_id`
```sql
user_id
account_id
current_account_id
```

**Join tables:** Alphabetical order
```ruby
# ❌ Fout
memberships_accounts

# ✅ Goed
account_memberships
```

---

## File Structure

### Standard Rails Structure

```
app/
├── assets/
│   ├── images/
│   └── stylesheets/
├── channels/
├── controllers/
│   ├── concerns/
│   └── *_controller.rb
├── helpers/
│   └── *_helper.rb
├── javascript/
│   ├── application.js
│   └── controllers/          # Stimulus controllers
├── mailers/
├── models/
│   ├── concerns/
│   └── *.rb
└── views/
    ├── icons/                # ⭐ Icon partials
    ├── layouts/
    ├── shared/               # Shared partials
    └── {resource}/           # Per-resource views
```

### Component Organization

**Shared Components:** `app/views/shared/`
```
shared/
├── _app_layout.html.erb      # Authenticated layout
├── _public_layout.html.erb   # Public layout
├── _sidebar.html.erb         # Navigation sidebar
├── _user_menu.html.erb       # User dropdown
├── _flash_messages.html.erb  # Alert messages
├── _error_messages.html.erb  # Form errors
└── _button.html.erb          # Reusable button
```

**Icons:** `app/views/icons/`
```
icons/
├── README.md                 # Icon documentation
├── _arrow_right.html.erb
├── _check.html.erb
├── _user.html.erb
└── ...
```

---

## Views & Templates

### Layout Structure

```erb
<!-- Gebruik layouts voor consistent page structure -->
<!DOCTYPE html>
<html>
  <head>
    <title>FundTogether</title>
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application" %>
    <%= javascript_importmap_tags %>
  </head>
  <body>
    <%= yield %>
  </body>
</html>
```

### View Organization

**1 view = 1 verantwoordelijkheid**

```erb
<!-- ✅ Goed: Gebruik partials -->
<div class="container">
  <%= render 'shared/flash_messages' %>
  <%= render 'header' %>
  <%= render 'content' %>
</div>

<!-- ❌ Fout: Alles in één file -->
<div class="container">
  <!-- 200 regels code... -->
</div>
```

### Comments in Views

```erb
<!-- Section Headers -->
<!-- ============================================ -->
<!-- User Profile Section -->
<!-- ============================================ -->

<!-- Inline Comments -->
<%# TODO: Add validation message %>
<%# NOTE: This is temporary until API is ready %>
```

---

## Components & Partials

### Icon System ⭐

**Locatie:** `app/views/icons/`
**Helper:** `app/helpers/icon_helper.rb`

**Gebruik:**
```erb
<!-- Basis -->
<%= icon :check %>

<!-- Met custom classes -->
<%= icon :user, class: "w-6 h-6 text-blue-500" %>

<!-- In een link -->
<%= link_to dashboard_path, class: "flex items-center gap-2" do %>
  <%= icon :chart, class: "w-5 h-5" %>
  <span>Dashboard</span>
<% end %>
```

**Beschikbare icons:** Zie `app/views/icons/README.md`

**Nieuwe icon toevoegen:**
```erb
<!-- app/views/icons/_my_icon.html.erb -->
<svg class="<%= css_class %>" fill="none" stroke="currentColor" viewBox="0 0 24 24">
  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="..."></path>
</svg>
```

### Button Component

**Locatie:** `app/views/shared/_button.html.erb`

**Gebruik:**
```erb
<!-- Primary button met icon -->
<%= render 'shared/button',
  text: 'Opslaan',
  icon: :check,
  variant: 'primary' %>

<!-- Link als button -->
<%= render 'shared/button',
  text: 'Bekijk',
  href: user_path(@user),
  icon: :arrow_right,
  variant: 'outline' %>
```

**Parameters:**
- `text` (required) - Button tekst
- `icon` (optional) - Icon symbol (bijv. `:check`)
- `variant` - `'primary'`, `'secondary'`, `'danger'`, `'success'`, `'outline'`
- `type` - `'submit'` (default), `'button'`
- `href` - Maakt een link ipv button
- `full_width` - `true` (default), `false`
- `disabled` - `true`, `false`

### Flash Messages

**Gebruik in controller:**
```ruby
# Success
redirect_to dashboard_path, notice: "Account succesvol aangemaakt"

# Error
redirect_to settings_path, alert: "Kon account niet verwijderen"

# Warning
flash[:warning] = "Je sessie verloopt binnenkort"
```

**Auto-dismiss:** Flash messages verdwijnen na 5 seconden (via Stimulus)

---

## CSS & Styling (Tailwind)

### Tailwind Utilities

**Gebruik utility classes voor styling**

```erb
<!-- ✅ Goed -->
<div class="flex items-center gap-4 p-4 bg-white rounded-lg shadow">
  <!-- content -->
</div>

<!-- ❌ Fout: Custom CSS voor simple layouts -->
<div class="custom-card">
  <!-- content -->
</div>
```

### Standard Sizes

**Spacing:**
```
gap-2  = 0.5rem (8px)
gap-3  = 0.75rem (12px)
gap-4  = 1rem (16px)
p-4    = 1rem padding
```

**Icon Sizes:**
```
w-4 h-4  = 1rem (16px)  - Small
w-5 h-5  = 1.25rem (20px) - Medium (default)
w-6 h-6  = 1.5rem (24px) - Large
w-8 h-8  = 2rem (32px)   - XL
```

**Rounded Corners:**
```
rounded     = 0.25rem
rounded-lg  = 0.5rem (default voor cards)
rounded-xl  = 0.75rem
rounded-full = 9999px (circles)
```

### Color Palette

**Primary (Blue):**
```
bg-blue-50   - Lightest background
bg-blue-600  - Primary buttons
bg-blue-700  - Hover state
text-blue-600 - Primary text
```

**Success (Green):**
```
bg-green-50
text-green-600
```

**Error (Red):**
```
bg-red-50
text-red-600
```

**Warning (Yellow):**
```
bg-yellow-50
text-yellow-600
```

**Neutral (Gray):**
```
bg-gray-50   - Light backgrounds
bg-gray-900  - Dark sidebar
text-gray-500 - Secondary text
text-gray-900 - Primary text
```

### Responsive Design

**Mobile First Approach:**
```erb
<!-- Base = mobile, lg: = desktop -->
<div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
  <!-- content -->
</div>

<!-- Hide on mobile, show on desktop -->
<div class="hidden lg:block">
  <!-- content -->
</div>
```

**Breakpoints:**
```
sm:  640px
md:  768px
lg:  1024px  (most used)
xl:  1280px
```

### Component Patterns

**Card:**
```erb
<div class="bg-white rounded-lg shadow-md p-6">
  <h2 class="text-xl font-bold mb-4">Title</h2>
  <p class="text-gray-600">Content</p>
</div>
```

**Button:**
```erb
<button class="px-4 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors">
  Click me
</button>
```

**Input:**
```erb
<input
  type="text"
  class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition"
>
```

---

## JavaScript & Stimulus

### File Structure

```
app/javascript/
├── application.js
└── controllers/
    ├── dapp_controller.js        # Web3/MetaMask
    ├── flash_controller.js       # Flash message auto-dismiss
    ├── dropdown_controller.js    # Dropdown menus
    └── confirm_modal_controller.js # Confirmation modals
```

### Stimulus Conventions

**Controller Naming:**
- File: `flash_controller.js`
- Data attribute: `data-controller="flash"`
- Class: `FlashController`

**Voorbeeld:**
```javascript
// app/javascript/controllers/flash_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message"]

  connect() {
    console.log("Flash controller connected")
  }

  dismiss() {
    this.element.remove()
  }
}
```

**Gebruik in view:**
```erb
<div data-controller="flash" data-flash-target="message">
  <button data-action="click->flash#dismiss">×</button>
</div>
```

---

## Rails Conventions

### Controllers

**RESTful Actions Volgorde:**
```ruby
class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]

  def index
  end

  def show
  end

  def new
  end

  def create
  end

  def edit
  end

  def update
  end

  def destroy
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email_address)
  end
end
```

**Custom Actions:** Plaats na RESTful actions, voor `private`

### Strong Parameters

**Altijd permit specifieke attributes:**
```ruby
# ✅ Goed
def account_params
  params.require(:account).permit(:name, :description)
end

# ❌ Fout
def account_params
  params.require(:account).permit!
end
```

### Redirects & Flash Messages

```ruby
# Success
redirect_to resource_path, notice: "Succesvol opgeslagen"

# Error
redirect_to edit_resource_path, alert: "Er ging iets mis"
render :edit, status: :unprocessable_entity
```

### Query Optimization

**Gebruik includes voor N+1 queries:**
```ruby
# ✅ Goed
@accounts = Account.includes(:users).all

# ❌ Fout (N+1)
@accounts = Account.all
# Later in view: account.users (extra query per account)
```

---

## Database & Models

### Monetary Values

**Gebruik integers (cents) voor geld:**
```ruby
# ✅ Goed
add_column :account_memberships, :balance_cents, :integer, default: 0

# ❌ Fout
add_column :account_memberships, :balance, :decimal
```

**Display helpers:**
```ruby
def balance
  balance_cents / 100.0
end

# In view
€<%= sprintf('%.2f', account.balance) %>
```

### Validations

**Volgorde:**
```ruby
class User < ApplicationRecord
  # Associations
  has_many :sessions

  # Validations
  validates :name, presence: true
  validates :email_address, uniqueness: true

  # Callbacks
  before_save :normalize_email

  # Scopes
  scope :active, -> { where(active: true) }

  # Instance methods
  def full_name
    # ...
  end

  # Class methods
  def self.search(query)
    # ...
  end

  private

  def normalize_email
    # ...
  end
end
```

### Enums

```ruby
# ✅ Goed: Symbol syntax (Rails 7+)
enum :role, [:admin, :member, :viewer]

# In database: integer kolom
# In code: user.admin? user.role = :member
```

---

## Testing

### Test Structure

```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "should be valid" do
    assert @user.valid?
  end

  test "name should be present" do
    @user.name = ""
    assert_not @user.valid?
  end
end
```

### Fixtures

**Locatie:** `test/fixtures/`

**Best Practices:**
- Minimale data voor tests
- Gebruik ERB voor dynamic content
- Readable names: `one`, `two`, `admin_user`

```yaml
# test/fixtures/users.yml
<% password_digest = BCrypt::Password.create("password") %>

one:
  name: Test User One
  email_address: one@example.com
  password_digest: <%= password_digest %>
```

### Controller Tests

```ruby
test "should get index" do
  get users_path
  assert_response :success
end

test "should require login" do
  # Without sign in
  get dashboard_path
  assert_redirected_to login_path
end
```

### Test Helpers

**Authentication:**
```ruby
setup do
  @user = users(:one)
  sign_in_as @user
end
```

---

## Security

### Pre-commit Hooks

**Automatische checks bij elke commit:**
1. Bundle Audit (vulnerable dependencies)
2. Brakeman (security scanner)
3. RuboCop Security cops
4. Custom anti-pattern detection
5. Rails test suite

**Zie:** `.git/hooks/pre-commit`

### Security Checklist

**Voor elke PR/commit:**
- [ ] No secrets in code
- [ ] Strong parameters gebruikt
- [ ] Authorization checks aanwezig
- [ ] SQL injection prevention
- [ ] XSS prevention (auto-escaped ERB)
- [ ] CSRF tokens actief

**Zie:** `SECURITY_AUDIT.md` voor volledige checklist

### Common Patterns

**Authorization:**
```ruby
# In controller
def authorize_admin!
  unless current_account_membership&.admin?
    redirect_to root_path, alert: "Unauthorized"
  end
end
```

**SQL Injection Prevention:**
```ruby
# ✅ Goed
User.where(email: params[:email])
User.where("email = ?", params[:email])

# ❌ Fout
User.where("email = '#{params[:email]}'")
```

---

## Git Workflow

### Branches

```
main          - Production code
feature/*     - New features
bugfix/*      - Bug fixes
hotfix/*      - Urgent production fixes
```

### Commit Messages

**Format:**
```
<type>: <subject>

<body>

<footer>
```

**Types:**
- `feat:` - Nieuwe feature
- `fix:` - Bug fix
- `refactor:` - Code refactoring
- `style:` - Code formatting
- `test:` - Tests toevoegen/updaten
- `docs:` - Documentatie
- `chore:` - Build/deps updates

**Voorbeeld:**
```
feat: Add reusable icon system

Created a DRY icon system to reduce duplication of SVG icons.

- Added 24 reusable icon partials
- Created icon helper method
- Updated all views to use new system

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

### Commit Checklist

Voor elke commit:
- [ ] Pre-commit hooks passeren
- [ ] Tests passeren (green)
- [ ] Code is formatted
- [ ] No console.logs/debuggers
- [ ] Commit message is descriptive

---

## Resources

### Documentation

- [Rails Guides](https://guides.rubyonrails.org/)
- [Tailwind CSS](https://tailwindcss.com/docs)
- [Stimulus Handbook](https://stimulus.hotwired.dev/)
- [Heroicons](https://heroicons.com/) - Icon set

### Project Docs

- `README.md` - Project setup
- `SECURITY_AUDIT.md` - Security checklist
- `app/views/icons/README.md` - Icon system docs
- `STYLEGUIDE.md` - This document

---

## Changelog

### v1.0 (2025-12-20)
- Initial styleguide
- Documented icon system
- Added component patterns
- Security guidelines
- Git workflow

---

**Vragen of suggesties?** Open een issue op GitHub of update deze styleguide via pull request.
