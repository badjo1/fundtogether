# Security Audit Checklist - FundTogether

Laatste update: 2025-12-20

## Hoe te gebruiken
- [ ] Review deze checklist elke sprint/release
- [ ] Pre-commit hook voert automatisch gemarkeerde items (🤖) uit
- [ ] Handmatige items worden periodiek gecontroleerd

---

## 1. Authentication & Authorization

### Authentication
- [x] Passwords worden veilig opgeslagen (bcrypt via has_secure_password)
- [x] Rate limiting op login endpoint (10 pogingen per 3 minuten)
- [x] Sessions worden veilig beheerd
- [ ] Password reset tokens expiren (check expiration logic)
- [ ] Multi-factor authentication overwegen voor admins
- [ ] Session timeout na inactiviteit

### Authorization
- [x] Admin authorization check voor account deletion
- [x] Users kunnen alleen data van eigen accounts zien
- [ ] Alle controller acties hebben authorization checks
- [ ] API endpoints hebben proper authentication
- [ ] File uploads (indien aanwezig) hebben authorization

**Critical Checks:**
```ruby
# Elke controller actie moet checken:
# 1. Is gebruiker ingelogd? (via Authentication concern)
# 2. Heeft gebruiker toegang tot deze resource?
# 3. Heeft gebruiker de juiste rol? (admin/member/viewer)
```

---

## 2. Input Validation & Sanitization

### Strong Parameters 🤖
- [x] Alle controller acties gebruiken strong parameters
- [ ] Geen mass assignment vulnerabilities
- [ ] Nested attributes zijn properly whitelisted

### Data Validation
- [x] Email validatie met proper regex
- [x] Wallet address validatie (Ethereum format)
- [ ] Amount/money validatie (geen negatieve bedragen)
- [ ] File upload validatie (type, size, content)

### XSS Prevention
- [x] ERB templates escapen output automatisch
- [ ] User-generated content wordt gesanitized
- [ ] JSON responses escapen proper
- [ ] Review raw/html_safe gebruik (moet minimaal zijn)

**Check commando's:**
```bash
# Zoek naar potentieel onveilig gebruik
grep -r "html_safe" app/
grep -r "raw(" app/
grep -r "sanitize" app/
```

---

## 3. SQL Injection Prevention 🤖

- [x] ActiveRecord queries gebruiken parameterized queries
- [ ] Geen string interpolation in queries
- [ ] Review custom SQL queries
- [ ] where() gebruikt hash syntax waar mogelijk

**Anti-patterns om te vermijden:**
```ruby
# ❌ SLECHT
User.where("email = '#{params[:email]}'")

# ✅ GOED
User.where(email: params[:email])
User.where("email = ?", params[:email])
```

**Check commando:**
```bash
# Zoek naar potentiële SQL injection
grep -r "where(\"" app/ | grep "#{"
```

---

## 4. CSRF Protection

- [x] Rails CSRF protection enabled (default)
- [x] Logout gebruikt DELETE/POST, niet GET
- [ ] API endpoints hebben proper CSRF handling
- [ ] External forms hebben authenticity_token

**Check:**
```bash
# Zoek naar GET requests met side effects
grep -r "get.*to:.*destroy\|delete\|update\|create" config/routes.rb
```

---

## 5. Sensitive Data & Secrets

### Credentials 🤖
- [ ] Geen secrets in code (gebruik Rails credentials/ENV vars)
- [ ] .env files zijn in .gitignore
- [ ] Database credentials niet hardcoded
- [ ] API keys in credentials.yml.enc
- [ ] Productie secrets verschillen van development

### Data Exposure
- [ ] Logs loggen geen passwords/tokens
- [ ] Error messages tonen geen sensitive info
- [ ] JSON responses filteren sensitive velden
- [ ] User.to_json exposed geen password_digest

**Check commando's:**
```bash
# Zoek naar mogelijke secrets in code
git secrets --scan
grep -r "password.*=.*['\"]" app/ --exclude-dir=test

# Check wat in logs komt
grep -r "logger\." app/
```

---

## 6. Blockchain/Web3 Specifiek

### Wallet Security
- [ ] Wallet addresses worden gevalideerd
- [ ] Private keys worden NOOIT opgeslagen
- [ ] Transaction signing gebeurt client-side
- [ ] Smart contract addresses zijn verified
- [ ] Gas limits zijn ingesteld

### Transaction Validation
- [ ] Transaction hashes worden opgeslagen
- [ ] Status updates zijn idempotent
- [ ] Double-spend prevention
- [ ] Amount validatie voor on-chain transactions

---

## 7. File Uploads & Assets

- [ ] File type whitelist (geen executables)
- [ ] File size limits
- [ ] Virus scanning bij upload
- [ ] Files opgeslagen buiten webroot
- [ ] Proper content-type headers
- [ ] Imagemagick/image processing libraries up-to-date

---

## 8. Dependencies & Gems 🤖

### Gem Security
- [ ] Bundler audit draait regelmatig
- [ ] Gems zijn up-to-date
- [ ] Geen known vulnerabilities

**Automatische checks:**
```bash
bundle audit check --update
bundle outdated
```

---

## 9. Code Quality & Static Analysis 🤖

### Brakeman (Security Scanner)
- [ ] Brakeman draait zonder warnings
- [ ] Kritieke issues zijn opgelost

### RuboCop (Code Quality)
- [ ] RuboCop security cops enabled
- [ ] Geen security offenses

**Check commando's:**
```bash
brakeman -q --no-pager
rubocop --only Security
```

---

## 10. Session & Cookie Security

- [ ] Cookies zijn httponly
- [ ] Cookies zijn secure (HTTPS only in productie)
- [ ] Session timeout geconfigureerd
- [ ] SameSite cookie attribute ingesteld

**Check in config:**
```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: '_fundtogether_session',
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax
```

---

## 11. API Security

- [ ] Rate limiting op API endpoints
- [ ] API versioning strategy
- [ ] Proper CORS configuration
- [ ] API authentication (tokens, OAuth)
- [ ] Request size limits

---

## 12. Database Security

- [ ] Database user heeft minimale privileges
- [ ] Sensitive columns encrypted at rest
- [ ] Database backups encrypted
- [ ] No default passwords
- [ ] SQL query timeouts ingesteld

---

## 13. Production Environment

### HTTPS & TLS
- [ ] Force SSL enabled in production
- [ ] TLS 1.2+ only
- [ ] HSTS headers ingesteld
- [ ] Certificate auto-renewal

### Headers & Policies
- [ ] Content Security Policy (CSP) headers
- [ ] X-Frame-Options header
- [ ] X-Content-Type-Options header
- [ ] Referrer-Policy header

**Check in production.rb:**
```ruby
config.force_ssl = true
config.ssl_options = { hsts: { expires: 1.year, subdomains: true } }
```

---

## 14. Logging & Monitoring

- [ ] Security events worden gelogd
- [ ] Failed login attempts tracked
- [ ] Abnormal activity alerts
- [ ] Log rotation configured
- [ ] Logs analyzed regelmatig

---

## 15. Error Handling

- [ ] Custom error pages (geen stack traces in productie)
- [ ] Errors loggen zonder sensitive data
- [ ] Proper exception handling
- [ ] Fallback responses voor edge cases

---

## Automated Security Check Commando's

Run deze commando's regelmatig (pre-commit hook doet dit automatisch):

```bash
# 1. Dependency vulnerabilities
bundle audit check --update

# 2. Security scanner
brakeman -q --no-pager

# 3. Code quality (security cops)
rubocop --only Security

# 4. Check for secrets
git secrets --scan || echo "Install git-secrets: brew install git-secrets"

# 5. Test suite
bundle exec rails test
```

---

## Emergency Response Plan

### Bij security incident:
1. **Isoleer** - Neem affected systeem offline indien nodig
2. **Assess** - Bepaal scope en impact
3. **Document** - Log alle acties en bevindingen
4. **Fix** - Implementeer hotfix
5. **Notify** - Inform affected users indien nodig
6. **Review** - Post-mortem en update deze checklist

### Contact
- **Developer**: [Jouw naam/email]
- **Security Team**: [Email]
- **Incident Response**: [Procedure]

---

## Recent Security Fixes

### 2025-12-20
- ✅ Fixed infinite recursion bug in ApplicationController
- ✅ Restored authorization check for account deletion
- ✅ Fixed CSRF vulnerability (logout GET → DELETE)
- ✅ Added authentication to UsersController
- ✅ Fixed incorrect database column names

---

## Volgende Review: [DATUM INVULLEN]
