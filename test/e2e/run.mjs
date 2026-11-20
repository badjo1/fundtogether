// Live Sepolia end-to-end run. Spends test ETH. Excluded from CI and `bin/rails test`.
//   FT_E2E_KEYS=<keys.json outside the repo> FT_E2E_OUT=<dir outside the repo> FT_E2E_SCREENS=<dir> \
//     node --experimental-websocket test/e2e/run.mjs A B C   # journeys; server first: test/e2e/serve.sh
import { browser, say, save, start, state } from "./harness.mjs"
import { assertSepolia, totalFunded } from "./chain.mjs"
import * as journeys from "./journeys.mjs"

await assertSepolia()
await start()
let failed = false
try {
  for (const name of process.argv.slice(2)) {
    const journey = journeys[`journey${name.replace("-", "_")}`]
    if (!journey) throw new Error(`unknown journey ${name}`)
    await journey()
  }
} catch (error) {
  failed = true
  say("ABORTED:", error.stack || error.message)
} finally {
  const { csp, console: consoleErrors, http5xx } = browser.problems
  say(`CSP violations: ${csp.length}`, csp.slice(0, 5).join(" | "))
  say(`Console errors: ${consoleErrors.length}`, consoleErrors.slice(0, 8).join(" | "))
  say(`HTTP 5xx: ${http5xx.length}`, http5xx.slice(0, 8).join(" | "))
  const spent = BigInt(state.startTotal) - await totalFunded()
  say(`Moved or spent from the three addresses so far: ${Number(spent) / 1e18} ETH`)
  save()
  await browser.stop()
}
process.exit(failed ? 1 : 0)
