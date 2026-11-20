# 01 - FundTogether audit and architecture

Commit audited: `3ec6826` on `main`. Repo not modified; the working tree still shows only the `Gemfile.lock` change that was there when the audit began (`tailwindcss-ruby` 4.1.18 to 4.3.4).

## How to read the evidence

- **[RUN]** Observed by running code. Unless stated otherwise this means a Rails integration test (test env, real cookies, `Current` reset between requests) from `audit_probe_test.rb` or `audit_probe2_test.rb`, run against a throwaway Postgres database that has since been dropped.
  - Probe code: `audit1/audit_probe_test.rb`
  - Second probe file: `audit1/audit_probe2_test.rb`
  - Raw output of the first file: `audit1/probe.out`
  - Probe IDs such as `A2` refer to `PROBE A2` lines. The probes print behaviour and assert nothing, so they must be rewritten as asserting regression tests.
- **[READ]** Established by reading code only.
- **[MEMORY]** From my knowledge of Tailwind, not checked against a v3 source here.

**Limits of this audit**

- No production boot and no browser session. "500" below means the exception reached the top of the test stack; in production it would render as a 500 page, which I inferred and did not observe.
- All JavaScript and visual claims are [READ], except for the CSS build comparison.
- I read only row counts from the development database and did not see production data.

**Toolchain [RUN]**

| Tool | Result |
|---|---|
| `bin/rails test` (scratch DB) | 122 runs, 386 assertions, 0 failures, 1 skip |
| `bin/rubocop` | 81 files, 0 offenses |
| `bin/bundler-audit` | No vulnerabilities |
| `bundle exec brakeman -q` | 0 warnings, on Brakeman 7.1.1 |
| `bin/brakeman` | **Exits non-zero (5)**, because `bin/brakeman:5` adds `--ensure-latest` and 8.1.0 exists |

The last row should make the `scan_ruby` job in `.github/workflows/ci.yml:22` and `config/ci.rb:10` fail until Brakeman is bumped; I did not run CI itself. Zero Brakeman warnings says nothing about authorization here: every critical below passed it.

## Top findings

1. Any registered user can rename or **delete any fund** by ID (A1, A2, A3).
2. Self-reported deposits become "confirmed" money with no chain involvement (A8).
3. The invitation link/QR/WhatsApp flow crashes on open (K1, K2).
4. Registration does not log the user in (E4). A logged-in user cannot accept an invitation directly (F2). The landing page after accepting returns 406 (G2).
5. Email verification on invitations can be bypassed three ways (H1, I1, J1), and acceptance never checks who the user is (G1, G3).
6. Members who belong to two funds are double-counted, so they are **charged twice** for expenses (C3), and a sole admin can leave a fund orphaned (Q2).
7. Pending-to-confirmed never updates balances. Only one of the two `after_commit` declarations survives (B1, B3).
8. Third-party CDN JavaScript runs on every page with no CSP or SRI (`app/views/layouts/application.html.erb:22`).

---

## 1. Architecture map and conventions

### Stack [READ]

- Ruby 3.4.6, Rails 8.1.1, Propshaft, importmap, Turbo, Stimulus, Postgres, Solid Queue/Cache/Cable, Thruster.
- `rqrcode` for QR codes.
- Importmap has no external pins (`config/importmap.rb:3-7`), which is good and worth keeping.
- `config/deploy.yml` and `.kamal` are absent, so the deploy target is unknown.

### Domain

| Model | File | Notes |
|---|---|---|
| `Account` | `app/models/account.rb` | This is the "fund". UI copy says "Account", "groepsaccount" |
| `AccountMembership` | `app/models/account_membership.rb` | Role admin/member/viewer, `balance_cents`, `active` |
| `Transaction` | `app/models/transaction.rb` | deposit/expense/transfer; drives balances by callback |
| `Invitation` | `app/models/invitation.rb` | Bearer token, 24h life, optional email verification |
| `User` | `app/models/user.rb` | Has `current_account`, a global per-user selected fund |
| `Session`, `Current` | `app/models/session.rb`, `current.rb` | Rails 8 auth generator |

### Routes and controllers

Authentication is on by default (`concerns/authentication.rb:5`) and opt-out via `allow_unauthenticated_access`. Dashboard, transactions, users and settings all scope through `current_account`. There is no authorization layer: no policy objects and no shared membership check.

Routes that exist without working actions or views:

| Route | Observed [RUN] | Cause |
|---|---|---|
| `GET /accounts`, `/accounts/:id`, `/accounts/:id/edit` | 406 (A4) | `app/views/accounts/` holds only `new.html.erb` |
| `PATCH /accounts/:id` invalid | Raises `MissingTemplate` (A4) | `accounts_controller.rb:35` |
| `transactions` show/update, `users` create/show/update/destroy, `users/invite`, `users/:id/remove` | 404 (A5) | `config/routes.rb:15,17-19` have no actions |
| `POST /accounts/:id/switch` | 404 (A5) | Route is GET (`routes.rb:6`); `_user_menu.html.erb:86` `method: :post` has no effect |

### View conventions [READ]

- **Layouts:** one real layout, `layouts/application.html.erb`. Pages wrap themselves with `render layout: 'shared/app_layout' do` (sidebar + topbar) or `render layout: 'shared/public_layout' do` (gradient, centred). Keep this pattern.
- **Partials:** `shared/_sidebar`, `_user_menu`, `_account_switcher`, `_flash_messages`, `_error_messages`, `_button`.
- **Icons:** `icon :name, class: "w-5 h-5"` (`app/helpers/icon_helper.rb:4`) renders `app/views/icons/_name.html.erb`, 27 Heroicons-outline partials that interpolate `css_class`. New icons follow the same template (`app/views/icons/README.md:59-68`). No wallet, link, clock or external-link icon exists yet.
- **`shared/_button`:** locals `text`, `variant` (primary/secondary/danger/success/outline), `icon`, `type`, `href`, `full_width` (default true), `disabled`, `data`. Only used on 4 public auth pages. App pages hand-write button classes.
- **Language:** Dutch, informal ("je"), Title Case on actions ("Nieuwe Storting", "Lid Uitnodigen"). Hardcoded in ERB, with no i18n keys. `config/locales/en.yml` is the only locale and `default_locale` is unset, which has these effects:
  - English leaks through validation errors.
  - `distance_of_time_in_words` and `strftime('%b')` output English inside Dutch sentences (`users/index.html.erb:140,145`, `invitations/show_accept.html.erb:105`).
  - `passwords_controller.rb:4,14,23,25,33`, `sessions_controller.rb:3,25`, `user.rb:55` and `dapp_controller.js:27` are English.
  - `settings/index.html.erb:107,120` show "Read-only" and "Disabled".
  - The layout has no `lang` attribute (`application.html.erb:2`).
- **Terms in use:** Storting, Uitgave, Overdracht, Saldo, Groepsleden, Uitnodiging, Splitsmethode, Instellingen, Gevarenzone.
- **Brand name is inconsistent:**
  - "Fund Together" (sidebar, mail)
  - "FUND TOGETHER" (`pages/home.html.erb:8`)
  - "Fundtogether" (title tag, `application.html.erb:4`)
  - **"En/Of-Rekening"** (`sessions/new.html.erb:8`)
- **Money format:** `€<%= sprintf('%.2f', x) %>`, dot decimal, floats. Negative balances render `€-50.00` and a test asserts this (`users_controller_test.rb:73`). List rows use U+2212 with `+`/`−` before the euro sign.

### Stimulus patterns [READ]

- Eager-loaded via `controllers/index.js:4`.
- The pattern is targets plus `classList` toggling of `hidden`, per `docs/STYLEGUIDE.md:581-611` ("never HTML in JS"). `clipboard_controller.js:17-22` breaks that rule.
- Document listeners are added in `connect` and removed in `disconnect`, but `dropdown_controller.js:19,23` calls `.bind` twice, so the listener is never removed: a leak across Turbo visits.
- `flash` auto-dismisses after 5s. `confirm_modal` handles the settings modals with Escape.

### Controller patterns [READ]

- Private `set_account` from `current_account`, with a redirect to `new_account_path` when nil.
- `redirect_to ..., notice:/alert:` in Dutch.
- `render ..., status: :unprocessable_entity` on failure.
- `params.require(...).permit(...)`.

### Test patterns [READ]

- Minitest, YAML fixtures (2 users, 2 accounts, `one` is admin and `two` is member of account one, nobody in account two), `sign_in_as` (`test/test_helpers/session_test_helper.rb`).
- `assert_select` is often pinned to Tailwind class chains (`users_controller_test.rb:46,49,61,73,81,101,138`; `complete_application_flow_test.rb:296`), so **restyling those elements breaks tests**.
- Headings are asserted by exact Dutch text.
- `test/system` is empty, so CI's `system-test` job runs nothing.
- No model tests exist for `Transaction`, `Account` or `AccountMembership`.

### Visual identity (preserve this) [READ]

Measured frequencies are grep counts across non-mailer views. All values are Tailwind class names rendered by CDN **v3.4.17**, the exact look today.

**Colour**

| Role | Classes |
|---|---|
| Primary | `bg-blue-600 hover:bg-blue-700 text-white` (26 uses) |
| Link | `text-blue-600 hover:text-blue-700` |
| Input focus | `focus:ring-2 focus:ring-blue-500 focus:border-blue-500` |
| Positive/deposit | `green-600` text and button; `bg-green-100` icon chip |
| Negative/expense | `red-600` text; `bg-red-100` chip |
| Warning | `yellow-50/200/600/800` |
| Info | `blue-50/200/600/700/800/900` |
| Admin badge and fourth stat accent | `purple-100/600/800` |
| Page background | `bg-gray-50` |
| Primary text | `text-gray-900` |
| Secondary text | `text-gray-600`, `text-gray-500` |
| Faint text | `text-gray-400` |
| Sidebar | `bg-gray-900`, header `bg-gray-800` |

- **Brand gradients:** public pages `bg-gradient-to-br from-blue-900 via-blue-800 to-purple-900` (`shared/_public_layout.html.erb:3`). Avatars and fund marks `bg-gradient-to-br from-blue-500 to-purple-600` with a white bold initial (`shared/_user_menu.html.erb:21,58`, `_account_switcher.html.erb:6`); inactive fund rows use `from-blue-400 to-purple-500`.
- **Member avatars:** inline hex palette `#FF6B6B #4ECDC4 #45B7D1 #96CEB4 #FFA07A #98D8C8 #6C5CE7 #FDA7DF` by index (`users/index.html.erb:54,68`).
- **Logo:** `public/icon.png` and `icon.svg` are a gold and grey tiger with butterfly, so the mark does not match the blue/purple UI. It appears on the home page (`pages/home.html.erb:6`). In-app brand mark is `icon :users` in `text-blue-400` (`_sidebar.html.erb:8`).
- **Dark mode:** none.

**Radii**

| Class | Count | Use |
|---|---|---|
| `rounded-lg` | 119 | Buttons, inputs, nested panels, list rows, nav items, icon chips |
| `rounded-xl` | 22 | **App cards and modals** |
| `rounded-2xl` | 7 | Public-page cards |
| `rounded-full` | 30 | Avatars, badges, empty-state circles |

`docs/STYLEGUIDE.md:442,510` says cards are `rounded-lg shadow-md`. **The code is the truth, not the styleguide.**

**Card patterns**

- **App card:** `bg-white rounded-xl p-6 shadow-sm border border-gray-100`, with optional `hover:shadow-md transition-shadow` (`pages/dashboard.html.erb:20,74`).
- **Stat card:** that card, then `flex items-center justify-between`; left side label `text-sm font-medium text-gray-600`, value `text-2xl font-bold text-gray-900 mt-1` (`text-3xl` on users), caption `text-sm text-gray-500 mt-1`; right side chip `p-3 rounded-lg bg-{colour}-100` with icon `w-6 h-6 text-{colour}-600` (`dashboard.html.erb:20-31`).
- **List row:** `bg-white rounded-lg p-4 shadow-sm border border-gray-100 hover:shadow-md transition-shadow`; icon chip `p-2 rounded-lg`; right-aligned amount `font-bold`, token `text-xs text-gray-500`, status badge (`dashboard.html.erb:79-105`, `transactions/index.html.erb:57-105`).
- **Nested row:** `flex items-center justify-between p-4 bg-gray-50 rounded-lg` (`users/index.html.erb:132`, `settings/index.html.erb:94`).
- **Public card:** `bg-white rounded-2xl shadow-2xl p-8` under a white circular icon `w-16 h-16 bg-white rounded-full`, `h1 text-3xl font-bold text-white`, subtitle `text-blue-200`, footer note `text-blue-100 text-sm` (`sessions/new.html.erb:5-9,13,74`).
- **Badge:** `px-2 py-1 text-xs rounded-full bg-{c}-100 text-{c}-800 font-medium`, mapping in `app/helpers/transactions_helper.rb:2-15`.
- **Info panel:** `p-4 bg-blue-50 rounded-lg` or with `border border-blue-200`, icon `w-5 h-5 text-blue-600 mt-0.5`, title `font-medium text-blue-900`, body `text-sm text-blue-700 mt-1` (`settings/index.html.erb:80-91`).
- **Error panel:** same shape in red with `icon :x_circle` (`settings/index.html.erb:13-27`).
- **Flash:** `mb-4 p-4 bg-{c}-50 border border-{c}-200 rounded-lg flex items-center gap-3` (`_flash_messages.html.erb`).
- **Empty state:** `w-16 h-16 bg-gray-100 rounded-full` circle with `w-8 h-8 text-gray-400` icon, grey text, primary CTA (`dashboard.html.erb:112-121`).
- **Modal:** `hidden fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4` around `bg-white rounded-xl max-w-md w-full p-6 shadow-2xl`, header chip `p-3 rounded-full bg-{c}-100`, footer `flex gap-3` with two `flex-1` buttons (`settings/index.html.erb:177-223`).
- **Danger zone:** card with `border-red-200`, heading `text-red-900`, rows `p-4 border border-red-200 rounded-lg` (`settings/index.html.erb:140-174`).

**Controls**

- **Primary, form scale:** `px-6 py-3 rounded-lg font-medium transition-colors`.
- **Primary, toolbar scale:** `px-4 py-2 rounded-lg flex items-center space-x-2` with `w-4 h-4` icon.
- **Secondary:** `border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50`.
- **Input:** `w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500`, `transition` on public pages.
- **Label:** `block text-sm font-medium text-gray-700 mb-2`.
- **Hint:** `text-xs text-gray-500 mt-1`.
- **Currency prefix:** absolute `€` at `left-4 top-1/2 -translate-y-1/2 text-gray-500`, input `pl-8`.
- **Toggle:** peer-based switch `w-11 h-6` (`accounts/new.html.erb:83`).

**Typography**

- Tailwind default system stack. No web font is loaded.
- Page title `text-2xl font-bold text-gray-900` in `h2`. Card title `text-lg font-bold text-gray-900 mb-4` (or `mb-6`). Weights: `font-medium` 115, `font-bold` 43, `font-semibold` 5.
- `font-mono` for addresses, hashes and invite URLs (`settings/index.html.erb:100`, `transactions/index.html.erb:85`, `invitations/success.html.erb:39`). Keep this for wallet addresses.

**Spacing and layout**

- Sidebar `fixed w-64`, content `lg:ml-64`, off-canvas under `lg` via `-translate-x-full` toggled by `dapp#toggleSidebar`.
- Top bar `h-16 bg-white shadow-sm border-b border-gray-200 px-4 lg:px-8`. Content `p-4 lg:p-8`.
- Page stack `space-y-6`. Stat grid `grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6`. Form pages `max-w-2xl mx-auto`. Public pages `max-w-md` (`max-w-lg` for the new-account page).
- Header row `flex items-center justify-between flex-wrap gap-4`.
- Nav item `flex items-center space-x-3 w-full px-4 py-3 rounded-lg`, active `bg-blue-600 text-white shadow-lg`, idle `text-gray-300 hover:bg-gray-800 hover:text-white` (`_sidebar.html.erb:21`).
- Icon sizes 4/5/6/8 (`app/views/icons/README.md:72-77`).
- Only custom animation: `animate-slide-in` (`application.html.erb:24-30`).

**Mail [READ]:** standalone inline-CSS templates with a `#3b82f6` to `#8b5cf6` gradient circle logo, `#2563eb` to `#1d4ed8` button, 12px card radius, `#fef3c7` warning box, HTML and text parts (`invitation_mailer/invite.html.erb:22-23,34,52,80`).

---

## 2. What works and must be preserved

| Capability | Evidence |
|---|---|
| Email/password login, logout, sessions | [RUN] F1; `sessions_controller_test.rb` |
| Password reset with enumeration-safe response, sessions destroyed afterwards | [RUN] `passwords_controller_test.rb`; [READ] `passwords_controller.rb:10-14,22` |
| Fund creation with admin membership | [RUN] `complete_application_flow_test.rb:226` (not atomic: `accounts_controller.rb:18-20`) |
| Multi-fund data model and fund switching, with a membership check | [RUN] A5 GET switch 302; [READ] `accounts_controller.rb:59` |
| Invitation creation with 256-bit token, 24h expiry, re-invite replacement | [RUN] `invitation_test.rb`; [READ] `invitation.rb:98,125-134` |
| Share UI: QR, copy, WhatsApp, direct mail | [RUN] `invitations_controller_test.rb:284` loads the page. Button behaviour not exercised |
| Accept with verified email via login | [RUN] G1. The membership is created, though the identity check is missing and the landing page fails |
| Mailers: Dutch HTML + text, correct sender | [RUN] `invitation_mailer_test.rb` |
| Dashboard, transaction list, filters, members page, settings form rendering | [RUN] `complete_application_flow_test.rb:64,102` |
| Icon helper, shared partials, flash, confirm modals, layouts | [RUN] pages render; JS behaviour [READ] |
| Clean importmap, Dockerfile, CI skeleton, Solid Queue config | [READ]. `bin/brakeman` step needs the fix above |
| Login and password-reset rate limits | [READ] `sessions_controller.rb:3`, `passwords_controller.rb:4`. Not exercised: test env uses `:null_store` (`config/environments/test.rb`) |

Keep `Invitation` token/expiry mechanics, `AccountMembership` as the fund access record, and the auth generator. Do not keep the balance-mutating `Transaction` flow.

---

## 3. What is fake or misleading

### Fake money

- **Deposits and expenses are self-declared.** `transactions_controller.rb:25` forces `status = "confirmed"`; `transaction.rb:79` defaults to confirmed. [RUN] A8: a member posts `amount_euros=1000000` and gets `status=confirmed`, `tx_hash=nil`, balance €50 to €1,000,050.
- A **viewer** can do this too, with token `DUMMY` (A7). `DUMMY` is offered as a choice (`transactions/new.html.erb:74`).
- `ETH` amounts are stored as cents and shown with a `€` sign (`transaction.rb:44-46`, `dashboard.html.erb:99`).
- "Totaal Groepssaldo" is the sum of those self-reported numbers (`account.rb:25-31`, `dashboard.html.erb:23-25`).
- **`tx_hash` is never written** by any code path. The Etherscan link (`transactions/index.html.erb:82-92`) is unreachable, hardcoded to mainnet and has no `rel="noopener"`.

### Fake wallet

- `dapp_controller.js:36-40` hardcodes `€150.25`. **However, that value cannot currently render**: no view defines a `userBalance` target. [READ] A grep of `app/views` for `userBalance`, `connectWallet` and `disconnectWallet` returns nothing.
- What actually happens today: `connect()` runs on every app page, `checkWalletConnection` overwrites the user-menu address with whatever `window.ethereum` reports (`:42-50`), then `loadUserBalance` should throw Stimulus' missing-target error inside an async function, an unhandled rejection. No browser run.
- The address is never sent to the server and is never verified.
- `User#wallet_address` and `Account#wallet_address` have **no writer** in any controller.
- `dapp` also owns `toggleSidebar`, so the mobile menu must survive when the wallet code is removed.
- `console.log` at `:7`.

### Fake settings

- `account.rb:2` `attr_accessor :min_deposit, :auto_convert, :notifications` are not columns (`db/schema.rb:33-40`).
- `accounts/new.html.erb:59-72,75-97` shows "Minimum storting", "Automatische EURe conversie", "Notificaties". `accounts_controller.rb:99` does not permit them, and `account.rb:97-99` only sets in-memory defaults. The input is discarded.
- `split_method` "Handmatig" and "Op basis van percentage" have no implementation; "Op basis van saldo" is broken (section 5).

### Marketing claims with no implementation

- `pages/home.html.erb:9,15,19,23,29,33`: "op de blockchain", "Gnosis Safe multisig beveiliging", "Monerium EURe fiat integratie", "Transparante on-chain boekhouding", "Verbind Wallet" (a plain link to `/dashboard`), "Ondersteund: MetaMask, WalletConnect, Coinbase Wallet".
- `shared/_sidebar.html.erb:46` "Powered by Blockchain".
- Meanwhile `settings/index.html.erb:84-87` honestly says "Blockchain functionaliteit uitgeschakeld", directly contradicting the home page.
- `registrations/new.html.erb:94` references "voorwaarden" that do not exist.
- `registrations/new.html.erb:53,55` and `passwords/edit.html.erb:27,31` say "Minimaal 8 karakters" but no validation exists. [RUN] E1: password `a` is accepted.
- `sessions/new.html.erb:75` "Veilig inloggen met Rails 8 Authentication".
- `_user_menu.html.erb:118` "Mijn Profiel" links to `#`.
- `users_controller.rb:11-12` makes "Actieve Leden" identical to "Totaal Leden" by construction.
- `users/index.html.erb:174-179` labels guest-rejected invitations "Geannuleerd".

### Dead code

**Files**
- `hello_controller.js`.
- `modal_controller.js` and `invitations/_form.html.erb`: the partial is never rendered and is the only thing using `modal#`.
- Empty helpers: `accounts_helper`, `application_helper`, `members_helper`, `pages_helper`, `registrations_helper`, `settings_helper`.
- `test/controllers/members_controller_test.rb` (`assert true`); empty `accounts_controller_test.rb` and `pages_controller_test.rb`.
- Empty `app/assets/stylesheets/application.css`.
- `app/views/pwa/*`, disabled in routes.

**Methods with no caller in `app`, `lib` or `test` [RUN grep]**
- `User#switch_to_account`, `ensure_current_account`, `transactions_in_account`, `active_in_account?`, `admin_in_account?`, `display_name`.
- `Account#remove_user`, `user_role`, `monthly_expenses`.
- `Transaction#confirm!`, scope `this_month`.
- `AccountMembership` scope `members_only`.
- Column `invitations.invitee_name`.

**Unreachable features**
- `transfer` has no UI.
- `viewer` role has no enforcement and no way to be granted.
- `AccountMembership#active` can never be set false by the app.

### Docs that do not match the code

| Claim | Reality |
|---|---|
| `docs/SECURITY_AUDIT.md:23` "[x] Admin authorization check voor account deletion"; `:320` "Restored authorization check" | Non-member deletes any fund [RUN A2] |
| `SECURITY_AUDIT.md:24` "[x] Users kunnen alleen data van eigen accounts zien" | IDOR on update and destroy [RUN A1, A2]; read paths are blocked only by missing templates |
| `test/controllers/invitations_controller_test.rb:94` "works in actual app"; `test/integration/invitation_acceptance_flow_test.rb:159` "working in production" | Logged-in accept does not work [RUN F2] |
| `docs/STYLEGUIDE.md:37` "Tailwind CSS 4.4" | 4.4 is the gem. Runtime is CDN v3.4.17 [RUN: `cdn.tailwindcss.com` 302 to `/3.4.17`] |
| `STYLEGUIDE.md:282` layout has `stylesheet_link_tag` | Absent. `application.html.erb:21-22` comment says stylesheets, next line is the CDN script |
| `STYLEGUIDE.md:442,510` card pattern | See visual identity section |
| `STYLEGUIDE.md:73-85` single quotes | RuboCop omakase enforces double (`docs/TESTING_BEST_PRACTICES.md:173`) |
| `STYLEGUIDE.md:787-789` integer enums | All enums are string-backed |
| `STYLEGUIDE.md:847-848` redirect to `login_path` | Actual redirect is `new_session_path` (`authentication.rb:34`) |
| `STYLEGUIDE.md:964` "No console.logs" | `dapp_controller.js:7` |
| `docs/README.md:8,65` "939 regels"; `:15` `REUSABLE_DOCS_SETUP.md`; `:88` 25 icons | 998 lines; file missing from `docs/`; 27 icons |
| `TESTING_BEST_PRACTICES.md:228` 385 assertions | 386 [RUN] |
| `STYLEGUIDE.md:980` README has project setup | `README.md` is marketing text only |
| `SECURITY_AUDIT.md:6-8` and `STYLEGUIDE.md:875` pre-commit hook | Exists only in the local `.git/hooks/`, not versioned, so nobody else gets it |

---

## 4. Security defects

Ordered by severity. "Exploit" assumes open registration, which exists. Since registration does not log the user in, the attacker just logs in afterwards.

### Critical

**C1. Any user can delete any fund.** `accounts_controller.rb:95` (`Account.find`), `:40` (`authorize_admin!` does not halt), `:102-106`.
- *Cause:* `authorize_admin!` is a plain method call, not a `before_action`, so its redirect does not stop execution. `@account.destroy` runs at `:45`, then the second `redirect_to` raises `DoubleRenderError`.
- *[RUN]* A2: non-member `DELETE /accounts/B` raises `DoubleRenderError`, `account_exists_after=false`. A3: same for a plain member on their own fund.
- *Exploit:* register, log in, loop `DELETE /accounts/1..N` with a valid CSRF token (IDs are sequential). All funds, ledger rows, memberships and invitations are gone (`account.rb:4-7` `dependent: :destroy`). The attacker sees 500s while data disappears. Once funds point to Safes, this would erase the app's record of a Safe that still holds money.

**C2. Any user can edit any fund.** `accounts_controller.rb:31-37,95`. No membership or role check.
- *[RUN]* A1: non-member `PATCH /accounts/B` gives 302, `name=PWNED`, `split=manual`.
- *Exploit:* rename a victim fund to mislead members, change split rules. Any future editable field on this model, such as a Safe address, becomes **fund redirection: contributors send money to the attacker's address**. The `set_account` scope must be fixed before any such column is added.

**C3. Third-party script on every page, no CSP.** `layouts/application.html.erb:22` loads `https://cdn.tailwindcss.com` with no SRI and it is a floating redirect to the latest v3 build. `config/initializers/content_security_policy.rb:7-29` is fully commented, so `csp_meta_tag` at `:10` is a no-op.
- *Exploit:* compromise of that CDN runs arbitrary JS on the future signing page. It can swap `to`/`data` in a Safe transaction before the wallet prompt, or display a fake proposal. A Safe owner signing a blind hash is the classic drain path, and it needs no server compromise.
- *Why first:* a strict `script-src 'self'` cannot coexist with this script, and it also injects styles at runtime, which blocks a strict `style-src`. Fix order is compiled CSS, then CSP (section 6).
- *CSP blockers [RUN grep]:* `transactions/new.html.erb:112-134` inline script, which carries actual form logic; `invitations/success.html.erb:86` `onclick`; `transactions/index.html.erb:28,37,46` `onchange`; `application.html.erb:23` inline `<style>`; `users/index.html.erb:68` inline style.

### High

**H1. Invitation email verification bypass by overwrite.** `invitations_controller.rb:76-92` is unauthenticated (`:10-13`), and it does not reset `email_verified_at`.
- *[RUN]* I1: anon overwrites email on a verified invitation: `email=attacker@evil.test verified=true ready=true`.
- *Also:* `check_invitation_validity` does not cover this action (`:7`), so it works on expired invitations (I3, mail sent) and rewrites accepted ones (I4).
- *Exploit:* anyone holding a forwarded link replaces the invitee's identity, and the app shows the attacker as verified. Also an unmetered mail relay: no rate limit, arbitrary recipient, Fund Together branding and the fund name in the mail.

**H2. Verification bypass by helper endpoint.** `invitations_controller.rb:163-177`. Requires login only, with no inviter or membership check, and auto-verifies at `:171`.
- *[RUN]* H1 probe: a non-member sets `attacker@evil.test`, `verified=true ready=true`.
- *Exploit:* the mailbox proof that the link/QR flow claims to enforce is skippable by anyone with a link and any account.

**H3. Verification token is not bound to the address.** `invitation.rb:38-41,47-53,91-94` signs only the invitation id; `invitations_controller.rb:98` compares only the invitation. Old tokens stay valid for 2h even after being replaced.
- *[RUN]* J1: token mailed to attacker verifies `victim@example.com`.
- *Exploit:* set own address, receive the token, change the address to the victim's, click the token. The victim's email is now "verified" and shown as such to the fund's members.

**H4. Accepting does not check identity.** `sessions_controller.rb:13-16`, `registrations_controller.rb:21-24`, `invitation.rb:55-62`. No comparison of user email against `invitation.email`. The `readonly` email at `registrations/new.html.erb:36` is client-side only.
- *[RUN]* G1: `two@example.com` logs in and consumes an invitation addressed to `intended@example.com`. G3: registers `attacker@example.com`, same result.
- *Exploit:* a forwarded or leaked link grants membership. This matters more once membership unlocks fund history and a place in the signer flow.

**H5. Stale invitation carried across users on one browser.** `invitations_controller.rb:129` writes to the cookie session; `authentication.rb:41-51` never calls `reset_session` on login or logout; `sessions_controller.rb:13-20` clears the token only on success.
- *[RUN]* T2, T3: user A's pending token stays through logout; once verified, the **next person who logs in on that browser is silently joined** to the fund.

**H6. No role enforcement anywhere.** `settings_controller.rb:8-14`, `invitations_controller.rb:16-39,148-160`, `transactions_controller.rb:22-34`.
- *[RUN]* A6: plain member renames fund and changes `split_method`. A7: viewer posts deposit and creates invitation; **inactive member** still reads the dashboard, posts expenses and edits settings (`application_controller.rb:17-19` never checks membership). M1, M2: member invites and deletes the admin's invitation. S1, S2: any logged-in non-member rejects any invitation by token, including already-accepted ones (`invitations_controller.rb:142-145`, `invitation.rb:64-66`).
- *Exploit:* a viewer changes how every member is charged, or fabricates a €1M deposit visible to everyone.

**H7. Login lockout via already-member accept.** `invitation.rb:59`, `sessions_controller.rb:16`. `add_member` raises `RecordInvalid`; the session token is never cleared.
- *[RUN]* R1-R3: three login attempts all return 422, no session cookie is set. This persists until the browser's session cookie is cleared or the invitation expires, since `ready_to_accept?` then turns false [READ].
- *Exploit:* an existing member clicks an invite to a fund they already belong to, then cannot log in on that browser.

**H8. No email confirmation on registration.** `registrations_controller.rb:14-37`; [RUN] E5, no mail enqueued. Weak passwords allowed [RUN] E1.
- *Exploit:* pre-register a victim's address before they are invited. Invitation flows then direct the real person to login (`invitations_controller.rb:131`). The real owner can recover through password reset, but anything the attacker attached before that, such as a future wallet link, would persist unless reset clears it.

### Medium

| ID | Location | Finding | Evidence |
|---|---|---|---|
| M1 | `accounts_controller.rb:58-65`, `routes.rb:6` | Fund switch is a state-changing GET. Top-level cross-site navigation passes `same_site: :lax`, so a link can silently change a victim's selected fund, and every money page acts on that implicit global. Two tabs on different funds also race | [READ]; GET 302 [RUN A5] |
| M2 | `sessions_controller.rb:3`, `passwords_controller.rb:4` | Rate limits exist only here. None on registration, `request_email_verification` (mail bomb), `send_email`, accept, transactions, password update. IP-keyed only | [READ] |
| M3 | `invitations_controller.rb:131-136` | Registered-email oracle, reachable with any token without verification: `/login` vs `/register` | [RUN] L6 |
| M4 | `production.rb:100-103` | `config.hosts` is commented out, and invite URLs use the request host (`invitations_controller.rb:21,170`) | [RUN] M3 probe: `http://evil.example/invitations/<token>/open`, test env. Impact limited: requires control of the inviter's request or a misrouting proxy |
| M5 | `authentication.rb:44`, `session.rb` | Sessions never expire: 20-year cookie, no idle timeout, no rotation, no device list | [READ] |
| M6 | `invitation.rb:98`, `schema.rb:47,52` | Invitation and verification tokens stored in plaintext. Bearer tokens in URL paths are written to logs, since `filter_parameters` filters params and not path segments | [READ]; log behaviour not run in production |
| M7 | `transactions_controller.rb:45`, `settings_controller.rb:26`, `accounts_controller.rb:99` | Unvalidated enum input gives unhandled errors: `ArgumentError` for token, type, split; `RangeError` for over-int4 amounts; `FloatDomainError` for `1e400` | [RUN] A6, A8 |
| M8 | `application_controller.rb:4` | `allow_browser versions: :modern` returned 406 to a Chrome 100 Android UA. In-app wallet browsers on older WebViews may hit this on the page they most need | [RUN] N1; real wallet UAs not tested |
| M9 | `.git/hooks/pre-commit` | Security gate is unversioned; `bin/brakeman` fails on `--ensure-latest` | [RUN] exit 5 |

### Low

- `invitations_controller.rb:9` skips CSRF on two GET actions, which is pointless but harmless.
- `invitations/success.html.erb:86` `onclick` interpolates an escaped URL. Its only real cost is as a CSP blocker.
- `_qr_code.html.erb:16` `html_safe` on generated SVG from a server-built URL. Not exploitable as far as I can see.
- `verify_email` is a state-changing GET, so mail scanners can trigger it (`routes.rb:32`).
- `show_accept` shows invitee email and inviter name to any token holder (by design of a bearer link).
- `show_accept.html.erb:43` nests a form within a form.
- `.git`-ignored `config/master.key` exists locally and is correctly untracked [RUN `git check-ignore`].

### Claims in the brief that needed correction

- **"Session cookie missing secure flag": not a production defect.** `authentication.rb:44` omits `secure:`, but `production.rb:31` `force_ssl` installs `ActionDispatch::SSL`, which flags cookies secure (`actionpack middleware/ssl.rb:76,94`). [READ] source, not exercised in a production boot. Setting it explicitly is cheap defence in depth. `force_ssl` also gives HSTS, and `SECURITY_AUDIT.md:238,240` has this unticked.
- **"€150.25" is hardcoded but not displayed.** No target exists in the views (section 3).
- **`AccountsController#show` is not a read IDOR today**, only because the template is missing (406). Adding a view without fixing `set_account` creates one immediately.
- **`Current` does not leak across requests in tests.** I tested this suspicion and it was false: P1 shows `Current.session` is empty after a request. The hidden-bug mechanism is weak assertions instead (next section).

### Tests that hide these defects [RUN and READ]

| Test | What it hides |
|---|---|
| `complete_application_flow_test.rb:37-47` "login form submission works" | Uses `password123`, but the fixture password is `password` (`users.yml:1`). Login **fails**, redirects, and passes on the login page's 200. [RUN] O1 |
| `complete_application_flow_test.rb:49-62` | Asserts only a redirect; hides that registration does not log in (E4) |
| `invitation_acceptance_flow_test.rb:58-60,98-100` | `follow_redirect!` then asserts only flash, ignoring 406 landing (G2) and the bounce to login after registration |
| `invitations_controller_test.rb:157-188` | Asserts the redirect to the accept page and never follows it, hiding the `NameError` (K1, K2). `:64` uses the only state that renders, a verified fixture |
| `invitations_controller_test.rb:92-95` | `skip` with a false justification; this is the suite's 1 skip |
| `accounts_controller_test.rb`, `pages_controller_test.rb` | Empty. `AccountsController` has only happy-path coverage through the flow test |
| `transactions_controller_test.rb` | One index test. Flow test asserts self-reported deposits as correct behaviour (`:138`) |
| All | No negative authorization test exists for any fund resource. No concurrency or role test |

---

## 5. Data-model limits for on-chain money

### The double `after_commit`: yes, Rails overwrites one

`transaction.rb:27-28` declares the same symbol twice. `active_support/callbacks.rb:273-278,645-663` treats same-symbol, same-kind callbacks as duplicates and deletes the earlier one. **Line 27 is dead**; only `if: :saved_change_to_id?, on: :create` survives. So it does *not* double-fire.

[RUN]:
- B1: one registered callback.
- B2: create confirmed gives +100, once.
- **B3: create pending then `confirm!` gives delta 0 and status confirmed.** Exactly the flow an on-chain confirmer would use silently loses the balance update.
- B4: confirmed then failed keeps the money; no reversal.
- B5: editing a confirmed amount from 100 to 5000 changes no balance.

Merging the two lines is **not** a fix: there is still no reversal or idempotency, and re-confirming would credit twice.

### Other callback and atomicity faults

- Balance updates run after commit, outside any transaction, with one `UPDATE` per member (`transaction.rb:89-109`). [RUN] V1, V2: a balance overflow raises `RangeError` after the row is already committed as confirmed, while the balance stays unchanged. The user sees an error and the ledger row persists.
- `invitation.rb:59-60`, `accounts_controller.rb:18-21`: multi-write flows have no transaction.

### Membership query bug (live money bug)

`account.rb:33-36,42-45`: `users.joins(:account_memberships)` joins the same table twice, and the alias is unfiltered, so each user appears once per membership **in any fund**.

[RUN]:
- C2: when `two` joins fund B, `active_users.count` for fund A goes from 2 to 3.
- C3: expense of 6000: `split_per_member=2000`, deltas **-2000 / -4000**. The two-fund member pays double.
- Q1, Q2: `admins.count` is 2 for a sole admin in two funds, so the guard at `accounts_controller.rb:76` passes and the fund ends with **0 admins**.

Member counts in the dashboard, sidebar and users page inherit the same inflation. Multi-fund use is the stated goal, so this triggers in normal use.

### `split_method` semantics [RUN D]

| Method | Expense | Each member debited | Sum vs amount |
|---|---|---|---|
| `equal` | 1001 | 500 | 1 cent lost, no remainder handling |
| `proportional` | 6000 | **0** | Nobody pays: integer division at `transaction.rb:67`, also uses the payer's share for everyone |
| `manual` | 6000 | **6000** | Everyone pays the full amount (`transaction.rb:72`) |
| `percentage` | 6000 | **6000** | Same |

The payer is never credited for paying: a "paid by" expense debits everyone, payer included. These are bookkeeping notions with no on-chain counterpart: a Safe pays out of pooled funds. Treat `split_method` as off-chain attribution at most.

### Column-level limits

- **`amount_cents`, `balance_cents` are int4** (`schema.rb:20,70`). Maximum €21,474,836.47; [RUN] A8 overflow raises. EURe has 18 decimals, so 1 token (10^18 base units) does not fit in int4 or int8. Use `numeric(78,0)` base units with token decimals alongside.
- **Float arithmetic in the money path:** `transaction.rb:41,45`, `account_membership.rb:32`, `account.rb:30,49`, and float formatting in views.
- **`balance_cents` is a mutable cache with no source of truth.** Nothing reconciles it with `transactions` ([RUN] V3: fixtures carry 10000 with 0 transactions) and tests set it directly (`users_controller_test.rb:55`). `leave` deletes it (`accounts_controller.rb:81`), so debt disappears when a member leaves. `Account#total_balance` is the sum of these caches and would not equal any Safe's balance.
- **Token enum** (`transaction.rb:23`): `DUMMY` and `ETH` in production; no chain id, contract address or decimals. Enum keys leak to the UI as lowercase `eure`/`dummy` ([RUN] A7; views print `transaction.token`).
- **`tx_hash` globally unique** (`schema.rb:83`): breaks when one transaction emits several transfers, as a Safe multisend does. Needs `(chain_id, tx_hash, log_index)`.
- **`from_user_id` NOT NULL** (`schema.rb:73`) contradicts `optional: true` (`transaction.rb:4`) and `dependent: :nullify` (`user.rb:7`, which would raise). On-chain deposits can come from unknown addresses, so a nullable user plus `from_address` is required.
- **`users.wallet_address` unique and singular** (`schema.rb:96`, `user.rb:18-20`):
  - One wallet per user. Contributing from one address and signing from a hardware wallet is not representable.
  - No two users can share a wallet.
  - Case-sensitive index, so checksummed and lowercase forms of one address count as different.
  - No proof of ownership (no SIWE) and no chain scope.
  - Mixed-case and `allow_nil` handling lets a blank string through validation while still hitting the index.
- **`accounts.wallet_address`:** validation commented out (`account.rb:11-12`), no index, no chain, no Safe metadata (threshold, owners, version, deploy state).
- **`status`, `token`, `transaction_type` nullable** at the DB level, with no check constraints (`schema.rb:74,76,77`).
- **Hard delete of financial history** via `dependent: :destroy` (`account.rb:6`). Should become archive-only.
- **`account_memberships.active` nullable** (`schema.rb:19`).

---

## 6. Tailwind situation

### Current state

- **Runtime:** only `<script src="https://cdn.tailwindcss.com">` (`application.html.erb:22`), which redirects to `/3.4.17` [RUN `curl -I`]. The layout has **no `stylesheet_link_tag`**, so the build is never loaded.
- **Compiled build:** `app/assets/builds/tailwind.css`, v4.3.4 per its header, from `app/assets/tailwind/application.css` (`@import "tailwindcss";` only). `/app/assets/builds/*` is gitignored (`.gitignore:39`). `Procfile.dev` watches it, and `assets:precompile` plus `db:test:prepare`/`test:prepare` rebuild it (`tailwindcss-rails lib/tasks/build.rake:35-42`), so Docker and CI already produce it.
- `Gemfile.lock` is uncommitted at `tailwindcss-ruby` 4.3.4, and the build's date matches. Commit or revert deliberately.

### What breaks on the move

**Measured:** extracted 306 class-like tokens from views, helpers and Stimulus, and looked each up in the build, using `audit1/tw.py`. After discarding non-classes (`pending`, `css_class` and so on) two remain missing:

| Class | Where | Effect | Fix |
|---|---|---|---|
| `bg-opacity-50` | `shared/_app_layout.html.erb:9`, `settings/index.html.erb:179,228`, `invitations/_form.html.erb:2` | **Mobile overlay and modal backdrops go fully opaque black** | `bg-black/50`, `bg-gray-600/50` |
| `animate-slide-in` | `pages/home.html.erb:3` | Defined in the inline `<style>` (`application.html.erb:24-30`), which keeps working until CSP removes it | Move to the Tailwind source CSS |

Inline scrollbar rules at `application.html.erb:31-47` must move too.

`flex-shrink-0` (24 uses by my count, which double-counts some) and `bg-gradient-to-br` **are present** in the 4.3.4 build [RUN]. No change is needed for these, despite being commonly listed as removed.

### Classes that exist but render differently

| Item | v3 today | v4 build | Basis |
|---|---|---|---|
| `blue-600` (primary) | `#2563eb` | `#155dfc` | v4 computed from build [RUN]; v3 [MEMORY], corroborated by mail templates |
| `blue-700` | `#1d4ed8` | `#1447e6` | Same |
| `green-600` | `#16a34a` | `#00a63e` | Same |
| `red-600` | `#dc2626` | `#e7000b` | Same |
| `purple-600` | `#9333ea` | `#9810fa` | Same |
| `yellow-600` | `#ca8a04` | `#d08700` | Same |
| `gray-900` | `#111827` | `#101828` | Same |
| `shadow-sm` (22 cards) | `0 1px 2px 0 rgb(0 0 0/.05)` | `0 1px 3px 0 #0000001a, 0 1px 2px -1px #0000001a` | v4 [RUN]; v3 [MEMORY] |
| `bg-gradient-to-br` | sRGB interpolation | `in oklab` | v4 [RUN]; v3 [MEMORY] |
| `<button>` cursor | `pointer` | `default` | [MEMORY], check after build |
| Placeholder colour | `gray-400` | current colour at 50% | [MEMORY] |
| `w-13` at `home.html.erb:6` | No-op; logo fills the 64px circle | 52px | v4 [RUN]; v3 [MEMORY] |

Blue-50/100, gray-50/100/200 are the same or within one step.

**Not an issue here:** the v4 default border colour change. [RUN grep] Every `border`, `border-t`, `border-b` has an explicit colour, except the `_button` outline, which has one on the same string. `rounded-lg/xl/2xl` use the same values [MEMORY].

### Minimal parity recipe

```css
/* app/assets/tailwind/application.css */
@import "tailwindcss";
@theme {
  --color-blue-600: #2563eb;
  --color-blue-700: #1d4ed8;
  /* ...one line for each colour above; confirm values first */
  --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
  --animate-slide-in: slideIn 0.3s ease-out;
}
@layer base {
  button:not(:disabled) { cursor: pointer; }
  ::placeholder { color: var(--color-gray-400); }
}
```

Then replace `<script>` with `stylesheet_link_tag "tailwind", "data-turbo-track": "reload"`, move keyframes and scrollbar rules into this file, and swap the 4 `bg-opacity-50` uses.

### How to verify

1. Re-run `tw.py` after any change: missing list must contain only non-classes. Add it as a small test or CI step.
2. Integration test: rendered HTML has no `cdn.tailwindcss.com`, and every response carries the CSP header.
3. Capture **computed styles on the CDN version before removing it**, to replace my [MEMORY] values: primary button background, card box-shadow, overlay alpha, placeholder colour, button cursor. Assert these in a system test afterwards. `test/system` is empty, and CI already has a job for it.
4. Screenshot at 375px and 1280px, before and after: home, login, new fund, dashboard, transactions, members, settings with both modals open, mobile sidebar open, invitation success.

Note that this build requires a modern browser for `oklch`/`@layer`, consistent with `allow_browser :modern`.

---

## 7. Recommended migration path

Each phase is independently shippable and keeps the suite green. Convert the relevant probes into asserting tests first and watch them fail.

### Phase 0: stop the bleeding (no chain code)

1. Authorization core: `current_user.accounts.find(params[:id])` in `set_account`, a `require_fund_role(:admin)` `before_action` that halts, and a check that `current_account` is an **active** membership. Admin-only: settings, destroy, invitation create and delete. Viewer: read-only. Add negative tests for each.
2. Registration: delete `registrations_controller.rb:45-54` so the concern's `start_new_session_for` is used (fixes E4); add password length validation. Keep the redirect target by using the concern's `after_authentication_url` or setting the return path.
3. Invitations: `before_action :resume_session` on unauthenticated actions (F2, F3); fix route names in `show_accept.html.erb:27,44,71` (K1, K2); honest flash on `accept!` returning false; wrap `accept!` in a transaction and handle already-member (R1-R3); reset `email_verified_at` on change and refuse changes after verification; apply validity checks to all token actions; bind the verification token to the address; restrict `send_invitation_email` to fund admins; `reset_session` on login and logout, preserving nothing except a token validated for this user.
4. **Decide policy (needs a product answer):** must the accepting user's email match the invitation? Recommendation: yes for email-addressed invites. For link/QR invites, treat them as bearer links and make that explicit, with admin approval before any on-chain role.
5. Fix `active_users` and `admins` (use `users.merge(AccountMembership.active)`-style with no second join). Fix or hide splits.
6. Add `accounts#show` or redirect accept to the fund's dashboard (set `current_account`) (G2).
7. Add rate limits; `config.hosts`; fix `bin/brakeman`; version the pre-commit hook or rely on CI. Fix the false tests listed in section 4.

### Phase 1: remove the CDN, add CSP

Compiled Tailwind with the parity recipe, then move inline JS into Stimulus (`transactions/new` is going away anyway; `onchange` to a small auto-submit controller; `onclick` to the existing `clipboard` controller). Ship CSP report-only, then enforce before any wallet page ships: `script-src 'self'` plus nonce; `connect-src` allowlist only for the RPC, Safe Transaction Service and WalletConnect endpoints; `frame-ancestors 'none'`; `object-src 'none'`. Vendor wallet libraries through importmap pins with `--download`, never from a CDN at runtime.

### Phase 2: stop lying

- Remove fake fields (`account.rb:2,97-99`, `accounts/new.html.erb:59-97`), `DUMMY`/`ETH` options, "Mijn Profiel", dead routes and dead controllers.
- Rewrite `home.html.erb` and `_sidebar.html.erb` claims to match what actually ships in each release; restore them feature by feature.
- Unify the brand name. Do not remove `dapp#toggleSidebar`: split it out into a `sidebar` controller and rewrite wallet logic separately.
- Disable `transactions#create` and the Storting/Uitgave buttons at the same time as the legacy treatment below.

### Phase 3: additive on-chain schema (the blockchain agent should own details)

Never reuse the old columns for on-chain values. Suggested shape:

- `wallets` (user, lowercase address, chain scope, `verified_at`, SIWE nonce). Many per user. Retire `users.wallet_address` after a release.
- `safes` (account_id, chain_id, address, threshold, deploy tx, state). Retire `accounts.wallet_address`.
- `tokens` config (chain_id, contract, symbol, decimals), replacing the enum.
- `chain_transfers` (chain_id, tx_hash, log_index, unique together; from/to address; nullable user; token; `numeric(78,0)` amount; block number; confirmations; status). Written only by a verifier reading the chain, never from client claims. A client may submit a hash, but it only creates a "pending check" item.
- `safe_proposals` and `safe_confirmations`, mirrored from the Safe Transaction Service.
- `ramp_orders`.
- **Display balances from chain data**, with per-member contributions derived from `chain_transfers`. No mutable balance cache. If caching is needed, make it rebuildable with a reconciliation job in `config/recurring.yml`.
- A worker must actually run: `plugin :solid_queue` needs `SOLID_QUEUE_IN_PUMA` (`config/puma.rb:38`), which neither the Dockerfile nor any deploy config sets. **Without it, `deliver_later` mail and any chain poller never run** in that image [READ].
- Membership does not grant signing rights. Safe owners are chain state, shown in the UI as distinct from app roles.
- Replace `current_account` on money pages with explicit `/accounts/:id/...` nested routes. The signing URL should name the fund and Safe. Keep `current_account` as a "last viewed" convenience only. Keep `Account` as the model name to avoid churn; change only the UI copy, if "Fonds" is wanted.

### Treatment of existing fake ledger data

Nothing in `transactions` or `balance_cents` is evidence of money. Across the local development DB [RUN counts]: 4 users, 9 accounts, 3 memberships, 4 transactions, **0 tx_hashes, 0 fund wallets**. That is dev data; **I have no view of production**, so check first whether production has real rows at all. If not, this reduces to a clean drop.

If rows exist:

1. **Never convert** legacy rows into `chain_transfers`, and never seed on-chain or displayed balances from them.
2. Add `transactions.origin` default `manual_legacy` for all existing rows. Stop setting `confirmed` on new records, then block new records entirely.
3. Rename `account_memberships.balance_cents` to `legacy_balance_cents` in two steps, removing every read from totals, dashboard stats, the member card and the user menu. Remove the `after_commit` and `increment/decrement_balance` in the same release.
4. Preserve history read-only in a section labelled, for example, "Handmatig geregistreerd (niet on-chain, niet geverifieerd)", with no "Bevestigd" badge, and offer a CSV export. Because the balances were corrupted by the bugs in section 5 (double debit, no reversal), label them as not reliable and not a claim on any money.
5. Notify members plainly once, before the change. Reconciling IOUs between members is outside the app's scope.
6. Delete `DUMMY` rows only after the export is offered. Keep the table until a retention decision is made, and never `dependent: :destroy` financial rows again.
7. Reset `accounts.wallet_address` and `users.wallet_address` usage: any existing value is unverified and must not be imported as a verified `wallet` or `safe`.

### Open decisions for the lead

1. Email-match policy on invitation acceptance (Phase 0, step 4).
2. Whether `split_method` survives at all, or is hidden until after launch.
3. Whether to match v3 colours exactly with `@theme` overrides (my recommendation, for parity) or accept the v4 palette.
4. Which chain, since `etherscan.io` and EURe availability both depend on it.
