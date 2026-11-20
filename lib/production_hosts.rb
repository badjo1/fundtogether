# Which Host headers production answers to. APP_HOST is required; ALLOWED_HOSTS adds a comma separated list.
# /up stays reachable by address, because load balancers and uptime checks do not send the public name.
module ProductionHosts
  EXCLUDE = ->(request) { request.path == "/up" }

  module_function

  def allowed(env = ENV)
    host = env.fetch("APP_HOST")
    [ host, "www.#{host}" ] + env.fetch("ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
  end
end
