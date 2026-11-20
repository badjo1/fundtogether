# Be sure to restart your server when you modify this file.
#
# Strict policy for every page. A signing page must not run script or load styles it did not get
# from this origin. See docs/ARCHITECTURE.md (CSP) and docs/research/wallet-onboarding.md section 9.
#
# Inline scripts and styles need a nonce. Inline event handlers (onclick=) and style= attributes
# cannot get one and are always blocked, so use Stimulus and classes for those.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self
    policy.img_src :self, :data
    # Evaluated per request through Chain::Registry: the public RPC origins of enabled chains only.
    # Operator endpoints from FUNDTOGETHER_RPC_URLS_* stay on the server and never appear here.
    policy.connect_src :self, -> { Chain::Registry.public_rpc_origins }
    policy.frame_src :none
    policy.object_src :none
    policy.base_uri :none
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # A fresh random nonce per request. Not session.id: this app authenticates with its own signed
  # cookie, so the Rails session id can be nil, which would give an empty nonce.
  # Importmap reads this nonce for its tags. Turbo reads it from csp_meta_tag for its progress bar.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]

  # same-origin: invitation tokens are in URL paths and must not reach other sites in a Referer.
  config.action_dispatch.default_headers.merge!(
    "Referrer-Policy" => "same-origin",
    "Permissions-Policy" => %w[
      accelerometer=() bluetooth=() camera=() geolocation=() gyroscope=() hid=() magnetometer=()
      microphone=() payment=() serial=() usb=() clipboard-write=(self) fullscreen=(self)
    ].join(", ")
  )
end
