require "net/http"

module Ramps
  # Manual check behind `bin/rails ramps:check`: HTTP HEAD on each URL in the catalog, reporting only
  # the status. Not run by tests or CI. A 200 says the host answered, not that the flow works.
  module LinkCheck
    TIMEOUT = 10
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131 Safari/537.36".freeze

    module_function

    def run(urls = Catalog.all_urls, output: $stdout)
      urls.each { |url| output.puts format("%-6s %s", status_of(url), url) }
      output.puts "Alleen de status is gecontroleerd. Een 200 bewijst niet dat de flow werkt."
    end

    def status_of(url)
      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.head(uri.request_uri, "User-Agent" => USER_AGENT)
      end
      response.code
    rescue StandardError => error
      "ERR #{error.class}"
    end
  end
end
