namespace :email do
  desc "Test email delivery in production"
  task test: :environment do
    email = ENV["TEST_EMAIL"]

    if email.blank?
      puts "❌ Error: TEST_EMAIL environment variable not set"
      puts "Usage: TEST_EMAIL=jouw@email.com rails email:test"
      exit 1
    end

    puts "📧 Sending test email to #{email}..."
    puts ""

    begin
      # Get first account and user for test
      account = Account.first
      user = User.first

      unless account && user
        puts "❌ Error: No account or user found in database"
        puts "Create an account and user first"
        exit 1
      end

      # Create temporary invitation for test
      invitation = Invitation.create!(
        email: email,
        account: account,
        invited_by: user,
        token: SecureRandom.hex(20),
        email_verification_token: SecureRandom.hex(20)
      )

      # Send email
      InvitationMailer.verify_email(invitation).deliver_now

      puts "✅ Email sent successfully!"
      puts ""
      puts "Details:"
      puts "  To: #{email}"
      puts "  From: #{ActionMailer::Base.default[:from]}"
      puts "  Subject: Bevestig je email voor #{account.name}"
      puts ""
      puts "Check your inbox (and spam folder)!"

      # Cleanup test invitation
      invitation.destroy

    rescue => e
      puts "❌ Error sending email:"
      puts "  #{e.class}: #{e.message}"
      puts ""
      puts "Debug info:"
      puts "  SMTP Address: #{ActionMailer::Base.smtp_settings[:address]}"
      puts "  SMTP Port: #{ActionMailer::Base.smtp_settings[:port]}"
      puts "  SMTP User: #{ActionMailer::Base.smtp_settings[:user_name]}"
      puts "  APP_HOST: #{ENV['APP_HOST']}"
      puts ""
      puts "Stack trace (first 5 lines):"
      puts e.backtrace.first(5).join("\n")
    end
  end

  desc "Show current email configuration"
  task config: :environment do
    puts "📧 Current Email Configuration"
    puts "=" * 50
    puts ""
    puts "Environment: #{Rails.env}"
    puts "Delivery method: #{ActionMailer::Base.delivery_method}"
    puts ""

    if ActionMailer::Base.smtp_settings.present?
      puts "SMTP Settings:"
      puts "  Address: #{ActionMailer::Base.smtp_settings[:address]}"
      puts "  Port: #{ActionMailer::Base.smtp_settings[:port]}"
      puts "  Username: #{ActionMailer::Base.smtp_settings[:user_name]}"
      puts "  Password: #{'*' * 20} (hidden)"
      puts "  Authentication: #{ActionMailer::Base.smtp_settings[:authentication]}"
    end

    puts ""
    puts "Default URL Options:"
    puts "  Host: #{ActionMailer::Base.default_url_options[:host]}"
    puts "  Protocol: #{ActionMailer::Base.default_url_options[:protocol]}"
    puts ""
    puts "Default From: #{ActionMailer::Base.default[:from]}"
    puts ""
    puts "Environment Variables:"
    puts "  APP_HOST: #{ENV['APP_HOST'] || '(not set)'}"
    puts "  RESEND_API_KEY: #{ENV['RESEND_API_KEY'] ? 'Set ✅' : 'Not set ❌'}"
    puts "  SENDGRID_API_KEY: #{ENV['SENDGRID_API_KEY'] ? 'Set ✅' : 'Not set ❌'}"
  end
end
