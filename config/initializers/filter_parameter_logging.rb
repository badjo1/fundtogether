# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc, :signature,
  /\Aaddress\z/, /\Anonce\z/
]

# Tokens in URL paths are bearer secrets: a reset link in a log is an account takeover for anyone with log access.
# Parameter filtering does not see paths, so each place that writes a URL gets its own rule (SECURITY_REVIEW M8).
module PathTokenFilter
  PATTERNS = [
    %r{\A/invitations/(?!success\b)[^/?]+},
    %r{/verify/[^/?]+},
    %r{\A/passwords/(?!new\b)[^/?]+},
    %r{\A/wallet/handoff/[^/?]+},
    %r{\A/email_bevestigen/(?!opnieuw\b)[^/?]+}
  ].freeze

  def self.filter(path)
    PATTERNS.reduce(path) do |clean, pattern|
      clean.gsub(pattern) { |match| match.sub(%r{[^/]+\z}, "[FILTERED]") }
    end
  end

  def filtered_path
    PathTokenFilter.filter(super)
  end
end

ActionDispatch::Request.prepend(PathTokenFilter)

# "Redirected to ..." lines.
Rails.application.config.filter_redirect += %w[/invitations/ /passwords/ /wallet/handoff/ /email_bevestigen/]

Rails.application.config.after_initialize do
  # "Enqueued ... with arguments: ..." would hold an invitation URL, and the mail log subscriber the whole body.
  ActionMailer::MailDeliveryJob.log_arguments = false
  ActionMailer::Base.logger = nil
end
