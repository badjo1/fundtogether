require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def csp_directive(name)
    header = response.headers["Content-Security-Policy"]
    assert header.present?, "expected a Content-Security-Policy header"
    header.split(";").map(&:strip).find { |directive| directive.start_with?("#{name} ") }.to_s
  end

  test "layout loads no third-party script and links the compiled stylesheet" do
    get login_path

    assert_response :success
    external = css_select("script[src], link[href]").map { |tag| tag["src"] || tag["href"] }.grep_v(%r{\A/(?!/)})
    assert_empty external
    assert_no_match "cdn.tailwindcss.com", response.body
    assert_select "link[rel=stylesheet][href*=tailwind]", 1
    assert_select "style", 0
  end

  test "policy is enforced, not report-only" do
    get login_path

    assert response.headers["Content-Security-Policy"].present?
    assert_nil response.headers["Content-Security-Policy-Report-Only"]
  end

  test "script-src and style-src allow self and a nonce, nothing unsafe" do
    get login_path

    %w[script-src style-src].each do |name|
      directive = csp_directive(name)
      assert_match(/'self'/, directive)
      assert_match(/'nonce-[A-Za-z0-9+\/=]+'/, directive)
      assert_no_match(/unsafe-inline|unsafe-eval|https:|\*/, directive)
    end
  end

  test "the remaining directives match the agreed policy" do
    get login_path

    assert_equal "default-src 'self'", csp_directive("default-src")
    assert_equal "img-src 'self' data:", csp_directive("img-src")
    assert_equal "frame-src 'none'", csp_directive("frame-src")
    assert_equal "object-src 'none'", csp_directive("object-src")
    assert_equal "base-uri 'none'", csp_directive("base-uri")
    assert_equal "form-action 'self'", csp_directive("form-action")
    assert_equal "frame-ancestors 'none'", csp_directive("frame-ancestors")
    assert_match %r{\Aconnect-src 'self'( https?://[^ ]+| wss?://[^ ]+)+\z}, csp_directive("connect-src")
  end

  test "connect-src lists exactly the public RPC origins of enabled chains" do
    get login_path
    origins = csp_directive("connect-src").split.drop(2)

    assert_equal Chain::Registry.public_rpc_origins, origins
    assert_includes origins, "https://ethereum-sepolia-rpc.publicnode.com"
    assert_not_includes origins, "https://mainnet.base.org", "a disabled chain must not be reachable"
  end

  test "enabling a chain widens connect-src, and operator endpoints never appear" do
    with_env("FUNDTOGETHER_CHAINS" => "sepolia,base") do
      get login_path
      assert_includes csp_directive("connect-src"), "https://mainnet.base.org"
    end
  end

  test "operator RPC endpoints stay out of the public accessor" do
    chains = Chain::Registry.send(:const_get, :CONFIG_PATH)
    raw = YAML.safe_load_file(chains, aliases: true).dig("chains", "sepolia")
    with_env("FUNDTOGETHER_RPC_URLS_SEPOLIA" => "https://rpc.example.com/v2/secret-key") do
      built = Chain::Registry.send(:build, "sepolia", raw)

      assert_includes built.rpc_urls, "https://rpc.example.com/v2/secret-key"
      assert_not_includes built.public_rpc_urls, "https://rpc.example.com/v2/secret-key"
      assert_no_match "secret-key", built.browser_config.to_json
    end
  end

  test "nonce is fresh per request and is the one on the inline importmap" do
    get login_path
    first = csp_directive("script-src")[/'nonce-([^']+)'/, 1]
    assert_select "script[type=importmap][nonce=?]", first
    assert_select "meta[name=csp-nonce][content=?]", first

    get login_path
    assert_not_equal first, csp_directive("script-src")[/'nonce-([^']+)'/, 1]
  end

  test "Permissions-Policy and Referrer-Policy are set" do
    get login_path

    assert_equal "same-origin", response.headers["Referrer-Policy"]
    assert_match(/camera=\(\)/, response.headers["Permissions-Policy"])
    assert_match(/clipboard-write=\(self\)/, response.headers["Permissions-Policy"])
  end

  test "logged-in pages have no inline handlers, inline styles or unnonced inline scripts" do
    sign_in_as users(:one)

    [ dashboard_path, users_path, settings_path, new_account_path ].each do |path|
      get path
      assert_response :success, "#{path} did not render"
      assert_no_match(/\son[a-z]+\s*=\s*["']/i, response.body, "inline handler on #{path}")
      assert_no_match(/\sstyle\s*=\s*["']/i, response.body, "inline style on #{path}")
      assert_select "script:not([src]):not([nonce])", 0
    end
  end

  test "view templates contain no inline handlers or inline styles" do
    templates = Rails.root.glob("app/views/**/*.erb").reject { |path| path.to_s.include?("mailer") }
    assert templates.any?

    offenders = templates.select { |path| path.read.match?(/\son[a-z]+[:=]\s*["']|\sstyle=["']|<style\b/i) }
    assert_empty offenders.map { |path| path.relative_path_from(Rails.root).to_s }
  end

  test "every class in the views exists in the compiled stylesheet" do
    css = Rails.root.join("app/assets/builds/tailwind.css").read
    tokens = Rails.root.glob("app/views/**/*.erb").reject { |path| path.to_s.include?("mailer") }.flat_map do |path|
      path.read.scan(/class(?:=|:\s*)"([^"]*)"/).flatten
    end
    candidates = tokens.flat_map { |value| value.gsub(/<%.*?%>|#\{.*?\}/m, " ").split }.uniq
    # Tailwind escapes "/", ":", "[", "]", "#" and "." in selectors. Markers such as "group" have no rule.
    markers = %w[group peer]
    missing = candidates.select { |klass| klass.match?(/\A[a-z-]/) }.reject do |klass|
      markers.include?(klass) || css.include?(".#{klass.gsub(/([^a-zA-Z0-9_-])/) { "\\#{$1}" }}")
    end

    assert_empty missing, "classes with no compiled rule; rebuild or fix them: #{missing.join(", ")}"
  end
end
