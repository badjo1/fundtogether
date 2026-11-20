// Manual, read-only: decodes a real Safe through the app's own code path. Sends nothing, needs no keys.
// Run from test/javascript: node live/read_only_check.mjs
import "../support/register.mjs"

const { createReader, createRpcProvider } = await import("safe/reader")
const { verifyDeployedSafe } = await import("safe/deploy")
const { SAFE_L2_SINGLETON } = await import("safe/constants")

const RPCS = ["https://ethereum-sepolia-rpc.publicnode.com", "https://sepolia.gateway.tenderly.co"]
const SAFE = process.argv[2] ?? "0x9cd26fca10660d4e2b207be5693a605150eb6243"

const reader = createReader(createRpcProvider(RPCS))
await reader.assertChain(11155111)

const [owners, threshold, nonce, singleton] = await Promise.all([
  reader.owners(SAFE), reader.threshold(SAFE), reader.nonce(SAFE), reader.singleton(SAFE)
])
console.log({ safe: SAFE, owners, threshold: threshold.toString(), nonce: nonce.toString(), singleton, canonicalSingleton: singleton === SAFE_L2_SINGLETON })
console.log({ modules: await reader.modules(SAFE), guard: await reader.guard(SAFE), fallbackHandler: await reader.fallbackHandler(SAFE) })

// A Safe with a module or guard must be refused, so a refusal here is a valid outcome to report.
try {
  await verifyDeployedSafe(reader, { safeAddress: SAFE, owners, threshold })
  console.log("verifyDeployedSafe: pass")
} catch (error) {
  console.log("verifyDeployedSafe: refused", error.code, error.details)
}
