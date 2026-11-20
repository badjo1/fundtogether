// Outbound CONNECT proxy for the server under test. Only the Sepolia RPC hosts pass, and none while
// the flag file exists. That makes "RPC down" real for Rails without touching Chain::Rpc.
import { createServer } from "node:http"
import { connect } from "node:net"
import { existsSync } from "node:fs"

const [port, downFlag] = process.argv.slice(2)
const ALLOWED = new Set(["ethereum-sepolia-rpc.publicnode.com", "sepolia.gateway.tenderly.co", "rpc.sepolia.ethpandaops.io"])

const server = createServer((req, res) => { res.writeHead(403); res.end() })
server.on("connect", (req, client, head) => {
  const [host, targetPort] = req.url.split(":")
  if (existsSync(downFlag) || !ALLOWED.has(host)) {
    client.end("HTTP/1.1 503 Service Unavailable\r\n\r\n")
    return
  }
  const upstream = connect(Number(targetPort), host, () => {
    client.write("HTTP/1.1 200 Connection Established\r\n\r\n")
    upstream.write(head)
    upstream.pipe(client)
    client.pipe(upstream)
  })
  const close = () => { upstream.destroy(); client.destroy() }
  upstream.on("error", close)
  client.on("error", close)
})
server.listen(Number(port), "127.0.0.1")
