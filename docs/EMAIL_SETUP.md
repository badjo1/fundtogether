# Email Setup voor Productie

## Overzicht

Je applicatie gebruikt email voor:
- **Uitnodigingen versturen** (`InvitationMailer#invite`)
- **Email verificatie** (`InvitationMailer#verify_email`)

In development gebruiken we `letter_opener` (emails openen in browser). Voor productie moet je een echte email service configureren.

---

## Stap 1: Kies een Email Service

### Aanbevolen Services

| Service | Prijs | Gratis Tier | Best voor |
|---------|-------|-------------|-----------|
| **SendGrid** | $15-20/maand | 100 emails/dag | Startups, makkelijke setup |
| **Mailgun** | $0.80/1000 emails | Eerste 3 maanden gratis | Flexibele pricing |
| **AWS SES** | $0.10/1000 emails | 62,000 gratis (via EC2) | AWS gebruikers |
| **Postmark** | $15/maand | 100 emails/maand | Transactionele emails |
| **Resend** | $0/maand | 3,000 emails/maand | Moderne API, developer-friendly |

### Onze aanbeveling: **Resend** of **SendGrid**
- **Resend**: Moderne service, generous gratis tier, simpel
- **SendGrid**: Bewezen, stabiel, goede documentatie

---

## Stap 2: Configureer Rails voor Productie

### Optie A: Resend (Aanbevolen)

#### 1. Verkrijg API Key
1. Maak account op [resend.com](https://resend.com)
2. Ga naar **API Keys**
3. Maak nieuwe API key
4. Sla key op (je ziet hem maar 1 keer!)

#### 2. Voeg Resend toe aan Gemfile
```ruby
# Gemfile
gem 'resend'
```

Installeer:
```bash
bundle install
```

#### 3. Configureer production.rb
```ruby
# config/environments/production.rb

# Verwijder deze regel (of zet op true):
config.action_mailer.raise_delivery_errors = true

# Update host naar je echte domein
config.action_mailer.default_url_options = {
  host: ENV.fetch("APP_HOST", "fundtogether.com"),
  protocol: "https"
}

# Configureer Resend
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: "smtp.resend.com",
  port: 465,
  user_name: "resend",
  password: ENV["RESEND_API_KEY"],  # API key uit environment
  authentication: :plain,
  ssl: true
}
```

#### 4. Stel Environment Variables in

**Voor Heroku:**
```bash
heroku config:set RESEND_API_KEY=re_123456789abcdef
heroku config:set APP_HOST=fundtogether.herokuapp.com
```

**Voor andere platforms (Render, Fly.io, etc.):**
Voeg toe in hun dashboard onder Environment Variables.

---

### Optie B: SendGrid

#### 1. Verkrijg API Key
1. Maak account op [sendgrid.com](https://sendgrid.com)
2. Ga naar **Settings > API Keys**
3. Maak nieuwe API key met "Mail Send" permissions
4. Sla key op

#### 2. Configureer production.rb
```ruby
# config/environments/production.rb

config.action_mailer.raise_delivery_errors = true

config.action_mailer.default_url_options = {
  host: ENV.fetch("APP_HOST", "fundtogether.com"),
  protocol: "https"
}

config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: "smtp.sendgrid.net",
  port: 587,
  domain: ENV.fetch("APP_HOST", "fundtogether.com"),
  user_name: "apikey",  # Letterlijk "apikey"
  password: ENV["SENDGRID_API_KEY"],
  authentication: :plain,
  enable_starttls_auto: true
}
```

#### 3. Stel Environment Variables in
```bash
heroku config:set SENDGRID_API_KEY=SG.xxxxxxxxxxxxx
heroku config:set APP_HOST=fundtogether.herokuapp.com
```

---

### Optie C: Gmail SMTP (NIET voor productie!)

⚠️ **Alleen voor testing/development**, niet aanbevolen voor productie!

```ruby
# config/environments/production.rb (ALLEEN VOOR TESTEN)

config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: "smtp.gmail.com",
  port: 587,
  user_name: ENV["GMAIL_USERNAME"],
  password: ENV["GMAIL_APP_PASSWORD"],  # App-specific password!
  authentication: :plain,
  enable_starttls_auto: true
}
```

**Limitaties:**
- Max 500 emails per dag
- Vaak geblokkeerd door Gmail
- Niet geschikt voor productie

---

## Stap 3: Verificeer Email Sender

### SPF en DKIM Records (belangrijk!)

Om emails niet in spam te laten belanden:

#### Voor custom domein (fundtogether.com)

1. **Voeg domein toe** in je email service (Resend/SendGrid)
2. **Configureer DNS records** die ze je geven:

**Voorbeeld Resend DNS records:**
```
Type: TXT
Name: @
Value: v=spf1 include:spf.resend.com ~all

Type: CNAME
Name: resend._domainkey
Value: resend._domainkey.resend.com
```

3. **Wacht op verificatie** (kan 24-48 uur duren)
4. **Test email delivery**

### From Address instellen

```ruby
# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: "noreply@fundtogether.com"  # Je geverifieerde domein!
  layout "mailer"
end
```

⚠️ **Belangrijk**: `from` email moet matchen met geverifieerd domein of je API key.

---

## Stap 4: Test Email in Productie

### In Rails Console (productie)
```ruby
# SSH naar je productie server of gebruik Heroku console
heroku run rails console

# Test email versturen
InvitationMailer.verify_email(Invitation.first).deliver_now

# Check output voor errors
```

### Test met rake task
```ruby
# lib/tasks/email_test.rake
namespace :email do
  desc "Test email delivery"
  task test: :environment do
    email = ENV["TEST_EMAIL"] || "jouw@email.com"

    puts "Sending test email to #{email}..."

    # Maak tijdelijke invitation voor test
    account = Account.first
    user = User.first

    invitation = Invitation.create!(
      email: email,
      account: account,
      invited_by: user,
      token: SecureRandom.hex(20),
      email_verification_token: SecureRandom.hex(20)
    )

    InvitationMailer.verify_email(invitation).deliver_now

    puts "✅ Email sent! Check #{email}"
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(5)
  end
end
```

**Run:**
```bash
# Lokaal
TEST_EMAIL=jouw@email.com rails email:test

# Heroku
heroku run TEST_EMAIL=jouw@email.com rails email:test
```

---

## Stap 5: Monitoring & Debugging

### Check Email Delivery Status

In je email service dashboard (Resend/SendGrid):
- **Activity Feed**: zie alle verstuurde emails
- **Bounces**: emails die niet aankwamen
- **Spam Reports**: emails die als spam gemarkeerd zijn

### Rails Logs Checken

```bash
# Heroku
heroku logs --tail | grep Mailer

# Lokale productie
tail -f log/production.log | grep Mailer
```

### Common Issues

#### 1. Email komt niet aan
```
❌ Check: Is API key correct ingesteld?
❌ Check: Is domein geverifieerd?
❌ Check: Zit email in spam folder?
```

#### 2. Authentication Failed
```ruby
# Check environment variables
heroku config | grep API_KEY
heroku config | grep APP_HOST

# Test SMTP verbinding
require 'net/smtp'
Net::SMTP.start('smtp.resend.com', 465) do |smtp|
  puts "✅ SMTP connection successful"
end
```

#### 3. URL's in email zijn verkeerd
```ruby
# Check in production.rb:
config.action_mailer.default_url_options = {
  host: "JUISTE-DOMEIN.com",  # ← Check dit!
  protocol: "https"
}
```

---

## Stap 6: Performance & Best Practices

### Gebruik Background Jobs

Voor betere performance, verstuur emails asynchroon:

```ruby
# app/mailers/invitation_mailer.rb
class InvitationMailer < ApplicationMailer
  def verify_email(invitation)
    # ... bestaande code
  end
end

# In je controller - gebruik deliver_later ipv deliver_now
InvitationMailer.verify_email(@invitation).deliver_later
```

Je hebt al **Solid Queue** geconfigureerd in `production.rb`:
```ruby
config.active_job.queue_adapter = :solid_queue
```

✅ Dit zorgt dat emails in achtergrond worden verstuurd.

### Rate Limiting

Voorkom spam door rate limiting toe te voegen:

```ruby
# app/models/invitation.rb
validate :check_rate_limit, on: :create

private

def check_rate_limit
  recent_count = Invitation
    .where(email: email)
    .where("created_at > ?", 1.hour.ago)
    .count

  if recent_count >= 3
    errors.add(:email, "Te veel uitnodigingen. Probeer later opnieuw.")
  end
end
```

---

## Complete Checklist

Voordat je live gaat:

- [ ] Email service gekozen en account aangemaakt
- [ ] API key verkregen en opgeslagen
- [ ] `production.rb` geconfigureerd met SMTP settings
- [ ] Environment variables ingesteld (`RESEND_API_KEY`, `APP_HOST`)
- [ ] Custom domein toegevoegd aan email service
- [ ] DNS records (SPF, DKIM) geconfigureerd
- [ ] Domein geverifieerd in email service
- [ ] `from` address ingesteld in `application_mailer.rb`
- [ ] Test email verstuurd en ontvangen
- [ ] Email templates getest (zien er goed uit?)
- [ ] Links in emails werken correct
- [ ] Emails komen niet in spam
- [ ] Background jobs draaien voor email delivery
- [ ] Monitoring ingesteld (dashboard checken)

---

## Voorbeeld: Complete Production Setup

```ruby
# config/environments/production.rb

Rails.application.configure do
  # ... andere settings ...

  # Email Configuration
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = true
  config.action_mailer.delivery_method = :smtp

  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST"),
    protocol: "https"
  }

  config.action_mailer.smtp_settings = {
    address: "smtp.resend.com",
    port: 465,
    user_name: "resend",
    password: ENV["RESEND_API_KEY"],
    authentication: :plain,
    ssl: true
  }

  # Solid Queue voor background jobs
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
end
```

```ruby
# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: "noreply@fundtogether.com"
  layout "mailer"
end
```

**Environment Variables:**
```bash
RESEND_API_KEY=re_abc123...
APP_HOST=fundtogether.com
```

---

## Support & Troubleshooting

### Resend Support
- **Docs**: https://resend.com/docs
- **Status**: https://status.resend.com

### SendGrid Support
- **Docs**: https://docs.sendgrid.com
- **Status**: https://status.sendgrid.com

### Test Email Deliverability
- **Mail Tester**: https://www.mail-tester.com
- **MXToolbox**: https://mxtoolbox.com

---

## Volgende Stappen

Na email setup:
1. **Test alle email flows** (invite, verify_email)
2. **Monitor eerste 100 emails** in dashboard
3. **Check spam score** met Mail Tester
4. **Configureer webhooks** voor bounces (optioneel)
5. **Setup alerts** voor delivery failures
