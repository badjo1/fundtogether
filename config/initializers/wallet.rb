# The origin wallet messages and handoff links are bound to. It comes from configuration,
# never from the request, so a spoofed Host header cannot influence what a wallet signs.
Rails.application.config.x.wallet.origin =
  ENV["FUNDTOGETHER_ORIGIN"].presence ||
  case Rails.env
  when "production" then "https://#{ENV.fetch('APP_HOST', 'fundtogether.app')}"
  when "test" then "https://fundtogether.test"
  else "http://localhost:3000"
  end

# Published on the transparency page, so anyone can compare it with vendor/javascript/viem.js and the rebuild in
# docs/VENDORED_JS.md. A test holds it equal to the file.
Rails.application.config.x.viem_sha256 = "10e91b8060efc63a42d70ebba9ab7b36d5af9b10ebef607c8e6c399a8f8cd781"
