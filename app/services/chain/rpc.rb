require "net/http"

module Chain
  # Read-only JSON-RPC client with endpoint fallback. Endpoints come from Chain::Registry only
  # and methods from a fixed allowlist, so there is no path from user input to a URL and no
  # way to send a transaction. Every failure raises; nothing here ever returns a default.
  class Rpc
    class Error < StandardError; end
    class TransportError < Error; end
    class RateLimited < Error; end
    class ServerError < Error; end
    class InvalidResponse < Error; end
    class RemoteError < Error; end
    class WrongChain < Error; end
    # The range or result size of eth_getLogs is too large for every endpoint. Callers halve.
    class RangeTooLarge < Error; end
    # The call itself reverted. This is an answer, not an outage, so no fallback.
    class Reverted < Error; end
    # All endpoints failed.
    class Unavailable < Error; end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15
    MAX_BODY_BYTES = 20.megabytes
    ALLOWED_METHODS = %w[eth_chainId eth_blockNumber eth_call eth_getCode eth_getStorageAt eth_getLogs
                         eth_getBlockByNumber eth_getTransactionReceipt eth_getBalance eth_getTransactionByHash].freeze
    BLOCK_BATCH = 100
    RANGE_ERROR = /range|too many|too large|exceed|more than|limit|pruned/i
    BLOCK_TAGS = %w[latest finalized safe].freeze

    # The HTTP seam. Replaced in tests; no gem is needed to stub it.
    class NetHttpTransport
      def post(url, body)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.write_timeout = READ_TIMEOUT
        request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
        request.body = body
        read(http, request)
      rescue SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError, EOFError,
             Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError => e
        raise TransportError, e.class.name
      end

      private

      def read(http, request)
        status = nil
        buffer = +""
        http.request(request) do |response|
          status = response.code.to_i
          response.read_body do |chunk|
            buffer << chunk
            raise InvalidResponse, "antwoord te groot" if buffer.bytesize > MAX_BODY_BYTES
          end
        end
        [ status, buffer ]
      end
    end

    class << self
      attr_writer :factory

      # The one place services get a client from, so tests can substitute a fake chain.
      def for(chain)
        @factory ? @factory.call(chain) : new(chain)
      end

      def reset_factory!
        @factory = nil
      end

      def verified_endpoints
        @verified_endpoints ||= Concurrent::Map.new
      end
    end

    attr_reader :chain

    def initialize(chain, transport: NetHttpTransport.new)
      @chain = chain
      @transport = transport
    end

    def call(method, params = [])
      raise ArgumentError, "methode niet toegestaan: #{method}" unless ALLOWED_METHODS.include?(method)

      failures = []
      chain.rpc_urls.each do |url|
        verify_endpoint(url)
        return perform(url, method, params)
      rescue Reverted
        raise
      rescue Error => e
        failures << e
        Rails.logger.warn("[chain.rpc] #{chain.key} #{URI(url).host} #{method}: #{e.class.name.demodulize}")
      end

      raise RangeTooLarge, method if failures.any?(RangeTooLarge)

      raise Unavailable, "#{chain.key} #{method}: #{failures.map { |e| e.class.name.demodulize }.join(', ')}"
    end

    def block_number
      Hex.quantity(call("eth_blockNumber"))
    rescue Hex::InvalidHex
      raise InvalidResponse, "eth_blockNumber"
    end

    def eth_call(to:, data:)
      expect_hex(call("eth_call", [ { to: Address.normalize(to), data: data, from: Address::ZERO }, "latest" ]))
    end

    def get_code(address)
      expect_hex(call("eth_getCode", [ Address.normalize(address), "latest" ]))
    end

    def get_storage_at(address, slot)
      value = expect_hex(call("eth_getStorageAt", [ Address.normalize(address), slot, "latest" ]))
      raise InvalidResponse, "eth_getStorageAt" if value.length > 66

      "0x#{value.delete_prefix('0x').rjust(64, '0')}"
    end

    # Returns an array of normalised logs. Raises on any malformed entry.
    def get_logs(address:, topics:, from_block:, to_block:)
      raw = call("eth_getLogs", [ { address: Address.normalize(address), topics: topics,
                                    fromBlock: Hex.from_uint(from_block), toBlock: Hex.from_uint(to_block) } ])
      raise InvalidResponse, "eth_getLogs" unless raw.is_a?(Array)

      raw.map { |log| normalize_log(log) }
    end

    # number_or_tag: an Integer or one of BLOCK_TAGS. Nil when the node does not have the block.
    def get_block(number_or_tag)
      raise ArgumentError, "blok" unless number_or_tag.is_a?(Integer) || BLOCK_TAGS.include?(number_or_tag)

      tag = number_or_tag.is_a?(Integer) ? Hex.from_uint(number_or_tag) : number_or_tag
      raw = call("eth_getBlockByNumber", [ tag, false ])
      return nil if raw.nil?

      raise InvalidResponse, "eth_getBlockByNumber" unless raw.is_a?(Hash)

      { number: quantity!(raw["number"]), hash: hash!(raw["hash"]), timestamp: quantity!(raw["timestamp"]) }
    end

    # Many block hashes in one request, so a number of rows cannot become a number of requests. An endpoint
    # that refuses a batch gets them one at a time. Returns { number => block or nil }.
    def get_blocks(numbers)
      numbers.each_slice(BLOCK_BATCH).reduce({}) do |found, slice|
        found.merge(block_batch(slice))
      rescue Error => e
        Rails.logger.warn("[chain.rpc] #{chain.key} batch: #{e.class.name.demodulize}")
        found.merge(slice.to_h { |number| [ number, get_block(number) ] })
      end
    end

    def get_balance(address)
      Hex.quantity(call("eth_getBalance", [ Address.normalize(address), "latest" ]))
    rescue Hex::InvalidHex
      raise InvalidResponse, "eth_getBalance"
    end

    # Nil when no node has heard of it. A pending transaction has no block yet.
    def get_transaction(tx_hash)
      raise ArgumentError, "geen tx-hash" unless Hex.hash?(tx_hash)

      raw = call("eth_getTransactionByHash", [ tx_hash ])
      return nil if raw.nil?

      raise InvalidResponse, "eth_getTransactionByHash" unless raw.is_a?(Hash) && Hex.bytes?(raw["input"])

      { hash: hash!(raw["hash"]), to: raw["to"]&.downcase, from: raw["from"]&.downcase, input: raw["input"].downcase }
    end

    # Nil when the transaction is not mined (or not known to this node).
    def get_receipt(tx_hash)
      raise ArgumentError, "geen tx-hash" unless Hex.hash?(tx_hash)

      raw = call("eth_getTransactionReceipt", [ tx_hash ])
      return nil if raw.nil?

      raise InvalidResponse, "eth_getTransactionReceipt" unless raw.is_a?(Hash) && raw["logs"].is_a?(Array)

      { tx_hash: hash!(raw["transactionHash"]), status: quantity!(raw["status"]),
        block_number: quantity!(raw["blockNumber"]), block_hash: hash!(raw["blockHash"]),
        logs: raw["logs"].map { |log| normalize_log(log) } }
    end

    private

    def block_batch(numbers)
      url = chain.rpc_urls.first
      verify_endpoint(url)
      ids = numbers.to_h { |number| [ SecureRandom.random_number(2**31), number ] }
      body = ids.map { |id, number| { jsonrpc: "2.0", id: id, method: "eth_getBlockByNumber", params: [ Hex.from_uint(number), false ] } }.to_json
      status, answer = @transport.post(url, body)
      check_status(status)
      rows = JSON.parse(answer)
      raise InvalidResponse, "geen batch" unless rows.is_a?(Array) && rows.length == numbers.length

      rows.to_h do |row|
        raise InvalidResponse, "batch" unless row.is_a?(Hash) && ids.key?(row["id"]) && !row["error"]

        raw = row["result"]
        [ ids.fetch(row["id"]), raw && { number: quantity!(raw["number"]), hash: hash!(raw["hash"]), timestamp: quantity!(raw["timestamp"]) } ]
      end
    rescue JSON::ParserError, TypeError, NoMethodError
      raise InvalidResponse, "batch"
    end

    # An endpoint pointing at the wrong network would make every later answer wrong and plausible.
    def verify_endpoint(url)
      return if self.class.verified_endpoints[url] == chain.chain_id

      answer = perform(url, "eth_chainId", [])
      unless answer.is_a?(String) && answer.match?(/\A0x[0-9a-fA-F]+\z/) && answer.to_i(16) == chain.chain_id
        raise WrongChain, chain.key
      end

      self.class.verified_endpoints[url] = chain.chain_id
    end

    def perform(url, method, params)
      id = SecureRandom.random_number(2**31)
      status, body = @transport.post(url, { jsonrpc: "2.0", id: id, method: method, params: params }.to_json)
      check_status(status)
      unwrap(body, id, method)
    end

    def check_status(status)
      return if status == 200
      raise RateLimited, "429" if status == 429
      raise ServerError, status.to_s if status >= 500

      raise TransportError, "HTTP #{status}"
    end

    def unwrap(body, id, method)
      envelope = begin
        JSON.parse(body)
      rescue JSON::ParserError, TypeError
        raise InvalidResponse, "geen JSON"
      end
      raise InvalidResponse, "geen JSON-RPC" unless envelope.is_a?(Hash) && envelope["jsonrpc"] == "2.0" && envelope["id"] == id

      raise_remote(envelope["error"], method) if envelope.key?("error") && !envelope["error"].nil?
      raise InvalidResponse, "geen result" unless envelope.key?("result")

      envelope["result"]
    end

    def raise_remote(error, method)
      raise InvalidResponse, "foutvorm" unless error.is_a?(Hash)

      code = error["code"]
      text = "#{error['message']} #{error['data']}"
      raise Reverted, error["message"].to_s.truncate(200) if method == "eth_call" && (code == 3 || text.match?(/revert/i))
      raise RateLimited, method if code == 429 || text.match?(/rate.?limit|too many requests/i)
      raise RangeTooLarge, method if method == "eth_getLogs" && text.match?(RANGE_ERROR)

      raise RemoteError, code.to_s
    end

    def expect_hex(value)
      raise InvalidResponse, "geen hex" unless Hex.bytes?(value)

      value.downcase
    end

    def quantity!(value)
      Hex.quantity(value)
    rescue Hex::InvalidHex
      raise InvalidResponse, "geen quantity"
    end

    def hash!(value)
      down = value.is_a?(String) ? value.downcase : value
      raise InvalidResponse, "geen hash" unless Hex.hash?(down)

      down
    end

    def normalize_log(log)
      raise InvalidResponse, "log" unless log.is_a?(Hash) && log["topics"].is_a?(Array)
      raise InvalidResponse, "log-adres" unless log["address"].is_a?(String) && log["address"].match?(Address::FORMAT)

      { address: log["address"].downcase, topics: log["topics"].map { |topic| hash!(topic) },
        data: expect_hex(log["data"]), block_number: quantity!(log["blockNumber"]), block_hash: hash!(log["blockHash"]),
        tx_hash: hash!(log["transactionHash"]), log_index: quantity!(log["logIndex"]), removed: log["removed"] == true }
    end
  end
end
