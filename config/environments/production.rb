require "active_support/core_ext/integer/time"
require_relative "../../lib/production_hosts"
require_relative "../../lib/trusted_proxies"

# Required: the host check and every link in mail depend on it. The image build has no runtime environment.
ENV["APP_HOST"] ||= "build.invalid" if ENV["SECRET_KEY_BASE_DUMMY"]
raise "APP_HOST is required in production (see docs/ARCHITECTURE.md, Production environment)" if ENV["APP_HOST"].blank?

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"


  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Who may report a client's address. See docs/ARCHITECTURE.md, Production environment.
  config.action_dispatch.trusted_proxies = TrustedProxies.parse(ENV["TRUSTED_PROXIES"])

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ProductionHosts::EXCLUDE } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Email Configuration - zie docs/EMAIL_SETUP.md voor volledige guide
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = true
  config.action_mailer.delivery_method = :smtp

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST"),
    protocol: "https"
  }

  # Resend SMTP Configuration (aanbevolen - zie docs/EMAIL_SETUP.md)
  # Uncomment en configureer environment variables: RESEND_API_KEY, APP_HOST
  config.action_mailer.smtp_settings = {
    address: "smtp.resend.com",
    port: 465,
    user_name: "resend",
    password: ENV["RESEND_API_KEY"],
    authentication: :plain,
    ssl: true
  }

  # Alternative: SendGrid SMTP Configuration
  # config.action_mailer.smtp_settings = {
  #   address: "smtp.sendgrid.net",
  #   port: 587,
  #   domain: ENV.fetch("APP_HOST", "example.com"),
  #   user_name: "apikey",
  #   password: ENV["SENDGRID_API_KEY"],
  #   authentication: :plain,
  #   enable_starttls_auto: true
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # DNS rebinding protection and the Host header attacks in docs/SECURITY_REVIEW.md, H3. X-Forwarded-Host is
  # checked by the same list. The health check is exempt, because it is called by address.
  config.hosts = ProductionHosts.allowed
  config.host_authorization = { exclude: ProductionHosts::EXCLUDE }
end
