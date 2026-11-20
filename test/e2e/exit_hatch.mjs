// Exit hatch: operate a fund's Safe with nothing of FundTogether. No app, no server, no database. Raw JSON-RPC,
// the Safe's own getTransactionHash, two owner keys, a hand-built execTransaction.
//   FT_E2E_KEYS=<keys.json> FT_E2E_OUT=<dir> node test/e2e/exit_hatch.mjs <safe> <recipient> <amount in base units> [token]
import { TOPICS, accountFor, addressOf, assertSepolia, encodeExec, encodeTxHashCall, joinSignatures, read, rpc, send, simulate } from "./chain.mjs"

const [safe, recipient, amount, token] = process.argv.slice(2)
const call = token
  ? { to: token, value: 0n, data: `0xa9059cbb${recipient.slice(2).toLowerCase().padStart(64, "0")}${BigInt(amount).toString(16).padStart(64, "0")}` }
  : { to: recipient, value: BigInt(amount), data: "0x" }
await assertSepolia()

const owners = (await read.owners(safe)).map((owner) => owner.toLowerCase())
const threshold = await read.threshold(safe)
const nonce = await read.nonce(safe)
const hash = await rpc("eth_call", [{ to: safe, data: encodeTxHashCall({ ...call, nonce }) }, "latest"])

const signatures = []
for (const name of ["a", "b", "c"]) {
  const address = await addressOf(name)
  if (!owners.includes(address) || signatures.length === threshold) continue
  signatures.push({ signer: address, signature: await (await accountFor(name)).sign({ hash }) })
}
if (signatures.length < threshold) throw new Error("not enough owner keys")

const data = encodeExec({ ...call, signatures: joinSignatures(signatures) })
const from = signatures[0].signer
const simulated = await simulate({ from, to: safe, data })
if (!simulated.ok) throw new Error(`simulation reverted: ${simulated.revert}`)

const name = (await addressOf("a")) === from ? "a" : (await addressOf("b")) === from ? "b" : "c"
const { hash: txHash, receipt } = await send(name, { to: safe, data })
const success = receipt.logs.some((log) => log.topics[0] === TOPICS.ExecutionSuccess && log.topics[1] === hash)
console.log(JSON.stringify({ hash: txHash, status: receipt.status, from, nonce, safeTxHash: hash, success }))
