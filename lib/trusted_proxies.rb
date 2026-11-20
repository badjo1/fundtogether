require "ipaddr"

# Who may tell us a client's address through X-Forwarded-For. Rate limits by IP depend on it. Comma separated
# addresses or ranges in TRUSTED_PROXIES; without it, only this machine (Thruster in the same container).
module TrustedProxies
  LOOPBACK = %w[127.0.0.1 ::1].freeze

  module_function

  def parse(value)
    list = value.to_s.split(",").map(&:strip).reject(&:empty?)
    (list.empty? ? LOOPBACK : list).map { |entry| IPAddr.new(entry) }
  end
end
