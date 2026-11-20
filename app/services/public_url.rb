# The origin for every link that leaves the app: mail, share links, QR codes. It comes from configuration,
# never from the request, because Host and X-Forwarded-Host are attacker input (docs/SECURITY_REVIEW.md, H3).
module PublicUrl
  module_function

  def options
    uri = URI(Rails.configuration.x.wallet.origin)
    { protocol: uri.scheme, host: uri.host, port: uri.port == uri.default_port ? nil : uri.port }
  end
end
