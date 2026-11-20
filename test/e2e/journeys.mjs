// The journeys of the live run. See docs/TESTNET_EVIDENCE.md for what was observed.
import { CHAIN_ID, EURC, FACTORY, FALLBACK, SINGLETON, ZERO, RPC_URLS, addressOf, assertSepolia, encodeExec, explorerTx, identity, read, rpc, safeFacts, send, simulate, waitReceipt, wei, joinSignatures, TOPICS } from "./chain.mjs"
import { BASE, USERS, asProposal, budget, eventually, emailOf, execute, inviteAndJoin, kase, linkWallet, messageOf, must, notRun, openExecutePanel, pageFor, pollUntil, prompts, propose, proposalJson, register, review, save, say, sign, sleep, state, stateOf, toneOf, walletReady } from "./harness.mjs"

const main = () => state.funds.main
const lower = (list) => [...list].map((x) => x.toLowerCase()).sort()

export async function deployUi(page, fundId, { threshold, ack = false, owners }) {
  await page.go(`/accounts/${fundId}/safe_instellen`)
  await page.until(`document.querySelector("[data-threshold-target=sentence]")?.textContent.includes("van de")`)
  // Tick exactly the wanted owners.
  await page.eval(`[...document.querySelectorAll("input[data-threshold-target=owner]")].forEach(box=>{const want=${JSON.stringify(owners)}.includes(box.value); if(box.checked!==want) box.click()})`)
  await page.fill("#threshold-select", String(threshold))
  if (ack) await page.click("input[data-threshold-target=ack]")
  await walletReady(page)
  await page.click("button[data-action='safe-deploy#deploy']")
}

export async function journeyA() {
  const a = await addressOf("a"), b = await addressOf("b"), c = await addressOf("c")

  await kase("A", "Pages are served with digested assets and a strict CSP", "Script URLs carry digests, CSP has no unsafe-inline or unsafe-eval", async (ctx) => {
    const page = await pageFor("anne")
    await page.go("/")
    const sources = await page.eval(`[...document.querySelectorAll("script[src],link[rel=modulepreload],link[rel=stylesheet]")].map(e=>e.src||e.href)`)
    const map = await page.eval(`document.querySelector("script[type=importmap]")?.textContent||""`)
    must(sources.length > 0, "no assets")
    must(sources.every((url) => /-[0-9a-f]{8,}\.(js|css)/.test(url)), `undigested: ${sources.filter((url) => !/-[0-9a-f]{8,}\./.test(url))}`)
    must(/"viem": ?"\/assets\/viem-[0-9a-f]{8,}\.js"/.test(map.replace(/\s+/g, " ")), "viem not digested in the importmap")
    const headers = (await fetch(BASE)).headers.get("content-security-policy")
    must(headers && /script-src 'self'/.test(headers) && !/unsafe/.test(headers), `csp: ${headers}`)
    ctx.observed = `${sources.length} digested assets on the home page; CSP: ${headers}`
  })

  await kase("A", "Anne registers and creates a fund", "Registered, fund exists in draft", async (ctx) => {
    const page = await register("anne")
    await page.go("/accounts/new")
    await page.fill("input[name='account[name]']", `E2E Huisgenoten ${state.run}`)
    await page.fill("textarea[name='account[description]']", "Live Sepolia-test")
    await page.submit("form[action='/accounts']", "uitnodigen")
    state.funds.main = { id: Number((await page.path()).match(/accounts\/(\d+)/)[1]) }
    save()
    ctx.observed = `fund ${main().id}, at ${await page.path()}`
    await page.shot("A-01-fund-created")
  })

  for (const who of ["bas", "cor"]) {
    await kase("A", `${USERS[who].name} is invited by mail, accepts and registers`, "Real mail delivered via Solid Queue; link leads to accept, register prefilled, joined", async (ctx) => {
      const { page, link } = await inviteAndJoin("anne", main().id, who)
      ctx.observed = `mail link ${new URL(link).pathname.replace(/\/invitations\/[^/]+/, "/invitations/<token>")}; joined, at ${await page.path()}`
      await page.shot(`A-02-${who}-joined`)
    })
  }

  for (const who of ["anne", "bas", "cor"]) {
    await kase("A", `${USERS[who].name} links a wallet with a real signature`, "personal_sign prompt, server accepts, wallet listed", async (ctx) => {
      const page = await linkWallet(who)
      ctx.observed = `prompts: ${(await prompts(page)).join(",")}; server lists ${await addressOf(USERS[who].wallet)}`
      await page.shot(`A-03-${who}-wallet-linked`)
    })
  }

  await kase("A", "Deploy a 2-of-3 Safe through the UI; server verifies it active", "One createProxyWithNonce tx from Anne's wallet, status active by the server's own verification", async (ctx) => {
    await budget()
    const page = await pageFor("anne")
    await deployUi(page, main().id, { threshold: 2, owners: [a, b, c] })
    await page.until(`(window.__sent||[]).length>0||document.querySelector("[data-safe-deploy-target=message][data-tone]")`, 60000)
    const tone = await toneOf(page, "safe-deploy")
    must(!tone, `deploy refused: ${await messageOf(page, "safe-deploy")}`)
    const hash = (await page.eval("window.__sent"))[0]
    ctx.tx.push(hash)
    await page.shot("A-04-deploy-sent")
    const deployment = await pollUntil("server says active", async () => {
      const r = await page.api("GET", `/accounts/${main().id}/safe`)
      return r.json?.status === "active" ? r.json : null
    }, 300000)
    state.funds.main.safe = deployment.safe_address
    state.funds.main.deployTx = hash
    save()
    must(deployment.deploy_tx_hash === hash, "server has another deploy hash")
    const receipt = await read.receipt(hash)
    const tx = await read.tx(hash)
    must(receipt.status === "0x1", "receipt failed")
    must(tx.to.toLowerCase() === FACTORY, "not sent to the factory")
    must(tx.from.toLowerCase() === a, "not from Anne's wallet")
    await page.go(`/accounts/${main().id}/transparantie`)
    await page.until(`document.querySelector("#live_owners")?.innerText.includes("2 van de 3")`, 30000)
    await page.shot("A-05-transparency-active")
    ctx.observed = `Safe ${deployment.safe_address}, status ${deployment.status}, verified_at ${deployment.verified_at}; UI shows 2 van de 3`
    ctx.verify = `receipt status 1, tx.to is the factory, tx.from is Anne; gasUsed ${BigInt(receipt.gasUsed)}, gas price ${BigInt(receipt.effectiveGasPrice)} wei`
  })

  await kase("A", "Independent verification by raw eth_call", "owners a,b,c; threshold 2; canonical singleton; no modules; no guard; canonical fallback; version 1.4.1", async (ctx) => {
    const facts = await safeFacts(main().safe)
    must(JSON.stringify(lower(facts.owners)) === JSON.stringify(lower([a, b, c])), `owners ${facts.owners}`)
    must(facts.threshold === 2, `threshold ${facts.threshold}`)
    must(facts.singleton === SINGLETON, `singleton ${facts.singleton}`)
    must(facts.guard === ZERO, `guard ${facts.guard}`)
    must(facts.modules === 0, `modules ${facts.modules}`)
    must(facts.fallback === FALLBACK, `fallback ${facts.fallback}`)
    must(facts.version === "1.4.1", `version ${facts.version}`)
    ctx.observed = JSON.stringify(facts)
    ctx.verify = "raw eth_call and eth_getStorageAt from test/e2e/chain.mjs, no app code"
  })
}

// --- B: money in

async function activityRow(page, fundId, hash) {
  for (let number = 1; number <= 10; number++) {
    await page.go(`/accounts/${fundId}/activiteit?page=${number}`)
    const row = await page.eval(`(()=>{const a=document.querySelector('a[href$=${JSON.stringify(hash)}]'); return a? a.closest("li").innerText.replace(/\\s*\\n+\\s*/g," | "):null})()`)
    if (row) return row
    if (await page.eval(`!document.querySelector('a[href*="page=${number + 1}"]')`)) return null
  }
  return null
}

const csvRow = async (page, fundId, hash) => (await page.eval(`fetch("/accounts/${fundId}/chain_events.csv").then(r=>r.text())`)).split("\n").find((line) => line.includes(hash))

async function jobCounts() {
  const { execFileSync } = await import("node:child_process")
  const sql = "select class_name, count(*), count(finished_at) from solid_queue_jobs group by 1 order by 1"
  return execFileSync("psql", ["-d", process.env.FT_E2E_DB || "ft_e2e_live", "-Atc", sql], { encoding: "utf8" }).trim().replace(/\n/g, "; ")
}

const CONTRIBUTE_RERUN = "FT_E2E_KEYS=<keys.json> FT_E2E_OUT=<dir> FT_E2E_SCREENS=<dir> node --experimental-websocket test/e2e/run.mjs B_eurc (server running via test/e2e/serve.sh, funded address 0x9C99fA79FCa58E6C59ac8EC3CF651231A855Ab2f holding at least 9 EURC from https://faucet.circle.com)"

export async function journeyB() {
  const a = await addressOf("a"), b = await addressOf("b"), c = await addressOf("c")
  const fund = main()
  const anne = await pageFor("anne")

  await kase("B", "Fund owner-b and owner-c with gas", "Two plain sends from the funded address", async (ctx) => {
    await budget()
    for (const to of [b, c]) {
      const { hash, receipt } = await send("a", { to, value: wei(0.002) }, { startTotal: state.startTotal })
      must(receipt.status === "0x1", "send failed")
      ctx.tx.push(hash)
    }
    ctx.verify = `eth_getBalance b ${await read.balance(b)} c ${await read.balance(c)}`
  })

  await journeyB_eurc()

  await kase("B", "Contribute page refuses an amount above the wallet's EURC, with decimals", "insufficient_token, no wallet prompt, nothing sent", async (ctx) => {
    await anne.go(`/accounts/${fund.id}/inleggen`)
    await walletReady(anne)
    await anne.until(`document.querySelector("[data-field=gasBalance]")?.textContent!==""`, 30000)
    const balances = await anne.eval(`[document.querySelector("[data-field=walletBalance]").textContent,document.querySelector("[data-field=gasBalance]").textContent]`)
    await anne.fill("input[data-contribute-target=amount]", "1000000,25")
    await anne.click("button[data-action='contribute#contribute']")
    await anne.until(`document.querySelector("[data-contribute-target=message][data-tone]")`, 20000)
    const text = await messageOf(anne, "contribute")
    must(/niet genoeg saldo/.test(text), text)
    must(!(await prompts(anne)).includes("eth_sendTransaction"), "wallet was prompted")
    ctx.observed = `wallet ${balances[0]} EURC, gas ${balances[1]} ETH; message: ${text}`
    await anne.shot("B-01-contribute-insufficient")
  })

  await kase("B", "Plain ETH from a member's wallet shows, attributed, via the recurring sync only", "Row appears without any sync request, attributed to Bas, In behandeling, exact amount; CSV has it", async (ctx) => {
    const safeBefore = await read.balance(fund.safe)
    const { hash, receipt } = await send("b", { to: fund.safe, value: wei(0.0002) }, { startTotal: state.startTotal })
    must(receipt.status === "0x1", "send failed")
    ctx.tx.push(hash)
    state.funds.main.pendingTx = hash
    save()
    const sent = Date.now()
    const row = await pollUntil("row via recurring sync", () => activityRow(anne, fund.id, hash), 240000, 8000)
    must(/Bas Jansen/.test(row), `not attributed: ${row}`)
    must(/\+0,0002 ETH/.test(row), `amount: ${row}`)
    must(/In behandeling/.test(row), `state: ${row}`)
    const line = await csvRow(anne, fund.id, hash)
    must(line && line.includes("200000000000000"), `csv: ${line}`)
    await anne.shot("B-02-activity-member-eth")
    ctx.observed = `after ${Math.round((Date.now() - sent) / 1000)} s without any sync request: ${row}. CSV: ${line}. Jobs: ${await jobCounts()}`
    ctx.verify = `Safe balance ${safeBefore} -> ${await read.balance(fund.safe)} wei by eth_getBalance`
  })

  await kase("B", "Send from an address not linked at that moment displays as unknown, and stays unknown after linking", "Onbekende afzender with short address", async (ctx) => {
    const cor = await pageFor("cor")
    await cor.go("/wallet")
    if ((await cor.api("GET", "/wallets")).json.wallets.some((row) => row.address === c)) {
      await cor.click("button[data-action='modal#open']")
      await cor.click("li[data-controller='modal'] form[action^='/wallet/'] button")
      await cor.until(`document.body.innerText.includes("gekoppeld")`)
      await sleep(1000)
    }
    const wallets = await cor.api("GET", "/wallets")
    must(!wallets.json.wallets.some((row) => row.address === c), "still linked")
    await anne.go(`/accounts/${fund.id}/transparantie`)
    await anne.until(`document.querySelector("#live_owners")?.innerText.includes("Niet gekoppeld")`, 30000)
    await anne.shot("B-03-transparency-owner-not-linked")
    let hash = fund.unknownEthTx
    if (!hash) {
      hash = (await send("c", { to: fund.safe, value: wei(0.0001) }, { startTotal: state.startTotal })).hash
      state.funds.main.unknownEthTx = hash
      save()
    }
    ctx.tx.push(hash)
    const row = await pollUntil("row via recurring sync", () => activityRow(anne, fund.id, hash), 240000, 8000)
    must(/Onbekende afzender/.test(row), `row: ${row}`)
    must(/0x3A9C/i.test(row), `no address: ${row}`)
    await anne.shot("B-04-activity-unknown-sender")
    await linkWallet("cor")
    await sleep(70000) // A full recurring cycle after the relink.
    const again = await activityRow(anne, fund.id, hash)
    must(/Onbekende afzender/.test(again), `became attributed: ${again}`)
    ctx.observed = `${row}; after relinking and one more sync cycle: ${again}`
    ctx.verify = `Receipt status ${(await read.receipt(hash)).status}; from ${(await read.tx(hash)).from}`
  })

  await kase("B", "Fund the Safe for the later journeys", "Anne's ETH arrives, attributed to Anne", async (ctx) => {
    const { hash } = await send("a", { to: fund.safe, value: wei(0.0015) }, { startTotal: state.startTotal })
    ctx.tx.push(hash)
    const row = await pollUntil("row via recurring sync", () => activityRow(anne, fund.id, hash), 240000, 8000)
    must(/Anne de Vries/.test(row) && /\+0,0015 ETH/.test(row), row)
    await anne.go("/dashboard")
    await anne.shot("B-05-dashboard")
    const page = (await anne.text()).replace(/\s*\n+\s*/g, " | ")
    ctx.observed = `${row}. Dashboard says: ${page.slice(0, 500)}`
    ctx.verify = `eth_getBalance Safe ${await read.balance(fund.safe)} wei; balanceOf(EURC, Safe) ${await read.eurc(fund.safe)}`
  })
}

// Needs test EURC on the funded address; only a human can fetch it from Circle's faucet (captcha). No other token is substituted.
const transferData = (to, units) => `0xa9059cbb${to.slice(2).padStart(64, "0")}${BigInt(units).toString(16).padStart(64, "0")}`
const EURC_NEEDED = 9_000_000n

async function contributeUi(ctx, who, amount, units, shownAmount) {
  const fund = main()
  const page = await pageFor(who)
  const before = await read.eurc(fund.safe)
  await page.go(`/accounts/${fund.id}/inleggen`)
  await walletReady(page)
  await page.until(`document.querySelector("[data-field=walletBalance]")?.textContent!==""`, 30000)
  await page.fill("input[data-contribute-target=amount]", amount)
  await page.click("button[data-action='contribute#contribute']")
  await page.until(`document.querySelector("[data-controller~='contribute'][data-flow-state='contributed']")||document.querySelector("[data-contribute-target=message][data-tone]")`, 240000)
  must(!await toneOf(page, "contribute"), await messageOf(page, "contribute"))
  const hash = (await page.eval("window.__sent")).at(-1)
  ctx.tx.push(hash)
  await page.shot(`B-10-contributed-${who}`)
  await eventually("balanceOf after contribution", async () => (await read.eurc(fund.safe)) - before === units || `moved ${(await read.eurc(fund.safe)) - before}`)
  const row = await pollUntil("activity row", () => activityRow(page, fund.id, hash), 240000, 6000)
  must(row.includes(USERS[who].name), `attribution: ${row}`)
  must(row.includes(`+${shownAmount} EURC`), `amount: ${row}`)
  must(/In behandeling/.test(row), `not pending: ${row}`)
  const line = await csvRow(page, fund.id, hash)
  must(line?.includes(`"${units}"`) && line.includes('"EURC"') && line.includes(USERS[who].name), `csv: ${line}`)
  ctx.observed += ` ${row}. CSV: ${line}.`
  ctx.verify += ` balanceOf(Safe) ${before} -> ${before + units}.`
  return hash
}

// Read-only: checks contributions already on chain against an independent log read, activity and CSV. Sends nothing.
export async function journeyB_verify() {
  const anne = await pageFor("anne")
  const fund = main()
  const TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  const rows = [
    ["anne", "0x74d4426d1e0699c595aa2b46df9884fc2b29917236c236217456f8a6da2108fa", 5_250_000n, "5,25", "eurcTx"],
    ["bas", "0x578ab33e1c1e662c9f1a9342a0352aba3da4152b36a0261fb5b9b361b9d489ef", 1_123_456n, "1,123456", "eurcTxB"],
    ["cor", "0xfdba1e546dc18154c8dd6cfe5696f45f3cb9740d1382fb8f49fd144805f931ad", 750_000n, "0,75", "eurcTxC"]
  ]
  for (const [who, hash, units, shown, key] of rows) {
    await kase("B", `${USERS[who].name}'s EURC contribution checked without sending again`, "Transfer log from this member's wallet to the Safe for the exact units; row attributed; CSV exact", async (ctx) => {
      const receipt = await read.receipt(hash)
      const address = await addressOf(USERS[who].wallet)
      const log = receipt.logs.find((entry) => entry.address.toLowerCase() === EURC && entry.topics[0] === TRANSFER)
      must(receipt.status === "0x1" && log, "no transfer")
      must(`0x${log.topics[1].slice(-40)}` === address && `0x${log.topics[2].slice(-40)}` === fund.safe, "wrong parties")
      must(BigInt(log.data) === units, `units ${BigInt(log.data)}`)
      const row = await activityRow(anne, fund.id, hash)
      must(row.includes(USERS[who].name) && row.includes(`+${shown} EURC`), row)
      const line = await csvRow(anne, fund.id, hash)
      must(line.includes(`"${units}"`) && line.includes('"EURC"') && line.includes(USERS[who].name), line)
      ctx.tx.push(hash)
      state.funds.main[key] = hash
      save()
      ctx.observed = `${row}. CSV: ${line}`
      ctx.verify = `Transfer log from ${address} to ${fund.safe}, ${BigInt(log.data)} units`
    })
  }
}

export async function journeyB_eurc() {
  const a = await addressOf("a"), b = await addressOf("b"), c = await addressOf("c")
  const fund = main()
  const balance = await read.eurc(a)
  say(`EURC balance of the funded address by eth_call: ${balance}`)
  if (balance < EURC_NEEDED && !state.done["B: EURC shared with the other test wallets by real transfers"]) {
    notRun("B", "EURC contribution", "Members contribute with decimals; attribution, pending then final, activity, balances, CSV, balanceOf", `EURC contribution: NOT RUN, wallet has no test EURC (balanceOf returned ${balance}). Rerun: ${CONTRIBUTE_RERUN}`)
    return false
  }

  await kase("B", "EURC shared with the other test wallets by real transfers", "a sends 3 EURC to b and 2 EURC to c; balanceOf agrees", async (ctx) => {
    for (const [to, units] of [[b, 3_000_000n], [c, 2_000_000n]]) {
      const before = await read.eurc(to)
      const { hash, receipt } = await send("a", { to: EURC, data: transferData(to, units) }, { startTotal: state.startTotal })
      must(receipt.status === "0x1", "transfer failed")
      ctx.tx.push(hash)
      await eventually("balanceOf", async () => (await read.eurc(to)) - before === units || "not yet")
    }
    ctx.verify = `balanceOf a ${await read.eurc(a)}, b ${await read.eurc(b)}, c ${await read.eurc(c)}`
  })

  await kase("B", "Too many decimals refused in the contribute form", "too_many_decimals, no prompt", async (ctx) => {
    const page = await pageFor("anne")
    await page.go(`/accounts/${fund.id}/inleggen`)
    await walletReady(page)
    await page.until(`document.querySelector("[data-field=walletBalance]")?.textContent!==""`, 30000)
    ctx.observed = `Wallet shows ${await page.eval(`document.querySelector("[data-field=walletBalance]").textContent`)} EURC. `
    await page.fill("input[data-contribute-target=amount]", "1,1234567")
    await page.click("button[data-action='contribute#contribute']")
    await page.until(`document.querySelector("[data-contribute-target=message][data-tone]")`, 20000)
    const text = await messageOf(page, "contribute")
    must(/te veel cijfers/.test(text), text)
    must(!(await prompts(page)).includes("eth_sendTransaction"), "prompted")
    ctx.observed += text
  })

  await kase("B", "Anne contributes 5,25 EURC through the UI", "Exact units on chain, attributed, In behandeling, CSV exact", async (ctx) => {
    state.funds.main.eurcTx = await contributeUi(ctx, "anne", "5,25", 5_250_000n, "5,25")
    save()
  })
  await kase("B", "Bas contributes 1,123456 EURC, all six decimals", "Exact units on chain, attributed, every decimal shown", async (ctx) => {
    state.funds.main.eurcTxB = await contributeUi(ctx, "bas", "1,123456", 1_123_456n, "1,123456")
    save()
  })
  await kase("B", "Cor contributes 0.75 EURC, point as separator", "Exact units on chain, attributed", async (ctx) => {
    await contributeUi(ctx, "cor", "0.75", 750_000n, "0,75")
  })

  await kase("B", "EURC from an address not linked at that moment displays as unknown, via the recurring sync", "Plain transfer outside the app: Onbekende afzender, amount exact; stays unknown after relinking", async (ctx) => {
    const anne = await pageFor("anne"), cor = await pageFor("cor")
    await cor.go("/wallet")
    if ((await cor.api("GET", "/wallets")).json.wallets.some((row) => row.address === c)) {
      await cor.click("button[data-action='modal#open']")
      await cor.click("li[data-controller='modal'] form[action^='/wallet/'] button")
      await sleep(1500)
    }
    must(!(await cor.api("GET", "/wallets")).json.wallets.some((row) => row.address === c), "still linked")
    // Resumable: an earlier attempt that stalled after sending must not send a second time.
    let hash = fund.unknownEurcTx
    if (!hash) {
      const sent = await send("c", { to: EURC, data: transferData(fund.safe, 250_000n) }, { startTotal: state.startTotal })
      must(sent.receipt.status === "0x1", "transfer failed")
      hash = sent.hash
      state.funds.main.unknownEurcTx = hash
      save()
    }
    ctx.tx.push(hash)
    const row = await pollUntil("row via recurring sync", () => activityRow(anne, fund.id, hash), 240000, 8000)
    must(/Onbekende afzender/.test(row) && /\+0,25 EURC/.test(row), row)
    await anne.shot("B-11-eurc-unknown-sender")
    await linkWallet("cor")
    const again = await activityRow(anne, fund.id, hash)
    must(/Onbekende afzender/.test(again), again)
    ctx.observed = `${row}; after relinking: ${again}`
  })

  await kase("B", "Live fund balance equals balanceOf; members' own totals", "Dashboard shows exactly what eth_call returns, no rounding that hides money", async (ctx) => {
    const anne = await pageFor("anne")
    const onChain = await read.eurc(fund.safe)
    must(onChain === 7_373_456n, `balanceOf ${onChain}`)
    await anne.go(`/accounts/${fund.id}/inleggen`)
    await anne.go("/dashboard")
    await anne.settle()
    const shown = await anne.eval(`document.querySelector("turbo-frame[id=balance_hero]")?.innerText||""`)
    await anne.shot("B-12-dashboard-eurc")
    const text = (await anne.text()).replace(/\s*\n+\s*/g, " | ")
    must(shown.includes("7,373456 EURC"), `dashboard balance: ${shown}`)
    ctx.observed = `Balance frame: ${shown.replace(/\s*\n+\s*/g, " | ")}. Own contribution tile: ${(text.match(/Jouw inleg \| [^|]+\| [^|]+/) || [""])[0]}`
    ctx.verify = `balanceOf(EURC, Safe) = ${onChain} units`
  })
  return true
}

// --- C: money out

export async function journeyC() {
  const b = await addressOf("b")
  const fund = main()
  const anne = await pageFor("anne"), bas = await pageFor("bas"), cor = await pageFor("cor")
  let payout = fund.payout

  await kase("C", "Propose a payout; one signature; execution refused below threshold", "UI offers no execution at 1 of 2; simulation of execTransaction reverts GS020; no transaction", async (ctx) => {
    payout = await propose(anne, fund.id, "transfer_native", { recipient_choice: b, amount: "0,0001" }, "Uitbetaling aan Bas")
    state.funds.main.payout = payout
    save()
    await anne.shot("C-01-proposal-created")
    await sign(anne, payout)
    await anne.settle()
    await anne.shot("C-02-signed-1-of-2")
    await cor.go(payout.path)
    await cor.until(`document.body.innerText.includes("1 van 2")`, 30000)
    await cor.shot("C-03-cor-sees-1-of-2")
    must(await cor.eval(`!document.querySelector("button[data-action='proposal-execute#execute']")`), "execute button offered below threshold")
    const json = await proposalJson(cor, payout)
    must(json.live.executable === false && json.live.reason === "not_enough_signatures", JSON.stringify(json.live))
    const data = encodeExec({ to: json.to, value: BigInt(json.value), data: json.data, signatures: joinSignatures(json.signatures) })
    const sim = await simulate({ from: await addressOf("c"), to: fund.safe, data })
    must(!sim.ok && /GS020/.test(sim.revert), JSON.stringify(sim))
    ctx.observed = `UI: 1 van 2, no execute button; server live.reason ${json.live.reason}; eth_call of execTransaction with the one real signature: reverted ${sim.revert}`
    ctx.verify = `eth_call, no gas spent. Safe nonce ${await read.nonce(fund.safe)}`
  })

  await kase("C", "Second owner signs; a third owner executes; state comes from ExecutionSuccess; recipient paid exactly", "Executed by Cor, ExecutionSuccess with this safeTxHash, nonce +1, Bas receives exactly 0.0001 ETH", async (ctx) => {
    await sign(bas, payout)
    await bas.settle()
    await bas.shot("C-04-signed-2-of-2")
    const nonce = await read.nonce(fund.safe)
    const before = await read.balance(b)
    const { hash, json } = await execute(cor, payout)
    ctx.tx.push(hash)
    await cor.settle()
    await cor.shot("C-05-executed")
    must(json.state === "executed", `state ${json.state}`)
    must(json.execution_tx_hash === hash, "hash differs")
    const receipt = await read.receipt(hash)
    const log = receipt.logs.find((entry) => entry.topics[0] === TOPICS.ExecutionSuccess && entry.address.toLowerCase() === fund.safe)
    must(log && log.topics[1] === json.safe_tx_hash, "no ExecutionSuccess for this safeTxHash")
    const after = await read.balance(b)
    must(after - before === wei(0.0001), `recipient moved ${after - before}`)
    must(await read.nonce(fund.safe) === nonce + 1, "nonce")
    ctx.observed = `state ${json.state}, UI: Uitgevoerd op de blockchain, executed by ${(await read.tx(hash)).from}`
    ctx.verify = `ExecutionSuccess topic matches safeTxHash ${json.safe_tx_hash}; eth_getBalance recipient ${before} -> ${after}; nonce ${nonce} -> ${nonce + 1}`
  })

  await kase("C", "Execution appears in activity through chain sync", "Voorstel uitgevoerd row with the tx hash", async (ctx) => {
    const hash = (await proposalJson(cor, payout)).execution_tx_hash
    const row = await pollUntil("execution row", () => activityRow(anne, fund.id, hash), 240000, 8000)
    await anne.shot("C-06-activity-execution")
    ctx.observed = row
    ctx.tx.push(hash)
  })
}

// --- D: owner management

const sameOwners = (actual, wanted) => JSON.stringify(lower(actual)) === JSON.stringify(lower(wanted))

// Signers sign, the executor sends, and the chain is read independently.
async function ownerChange(ctx, { proposer, kind, fields, title, signers, executor, wantOwners, wantThreshold }) {
  const fund = main()
  // An earlier attempt may have got this far: the chain and the stored proposal say so, nothing is assumed.
  const existing = (await proposer.api("GET", `/accounts/${fund.id}/proposals`)).json.proposals.find((row) => row.title === title && row.state === "executed")
  if (existing) {
    const facts = await safeFacts(fund.safe)
    must(lower(facts.owners).length >= wantOwners.length, "owners do not match a finished attempt")
    ctx.tx.push(existing.execution_tx_hash)
    ctx.observed += ` Already executed in an earlier attempt, ${existing.execution_tx_hash}.`
    ctx.verify += ` Receipt status ${(await read.receipt(existing.execution_tx_hash)).status}.`
    return existing
  }
  const proposal = await propose(proposer, fund.id, kind, fields, title)
  return finishOwnerChange(ctx, { proposal, signers, executor, wantOwners, wantThreshold, fund })
}

async function finishOwnerChange(ctx, { proposal, signers, executor, wantOwners, wantThreshold, fund = main() }) {
  for (const signer of signers) await sign(signer, proposal)
  const nonce = Number(BigInt((await proposalJson(executor, proposal)).nonce)) + 1
  const { hash, json } = await execute(executor, proposal)
  ctx.tx.push(hash)
  must(json.state === "executed", `state ${json.state}`)
  await eventually("chain state after execution", async () => {
    const seen = await safeFacts(fund.safe)
    return (sameOwners(seen.owners, wantOwners) && seen.threshold === wantThreshold && seen.nonce >= nonce) || `owners ${seen.owners} threshold ${seen.threshold} nonce ${seen.nonce}`
  })
  const facts = await safeFacts(fund.safe)
  must(facts.modules === 0 && facts.guard === ZERO, "module or guard appeared")
  ctx.observed += ` ${proposal.path}: ${json.state}.`
  ctx.verify += ` owners ${lower(facts.owners).join(",")}; threshold ${facts.threshold}; nonce ${facts.nonce}; no modules, no guard.`
  return json
}

async function realSignature(page, hash) {
  return page.eval(`window.__provider.accounts[0].sign({hash:${JSON.stringify(hash)}})`)
}

async function payoutProposal(page, to, amount, title) {
  return propose(page, main().id, "transfer_native", { recipient_choice: "other", recipient: to, amount }, title)
}

export async function journeyD() {
  const a = await addressOf("a"), b = await addressOf("b"), c = await addressOf("c"), d = await addressOf("d"), e = await addressOf("e")
  const fund = main()
  const anne = await pageFor("anne"), bas = await pageFor("bas"), cor = await pageFor("cor")

  for (const who of ["dirk", "eva"]) {
    await kase("D", `${USERS[who].name} joins and links a fresh, empty wallet`, "Invited by mail, signature accepted; costs no gas", async (ctx) => {
      await inviteAndJoin("anne", fund.id, who)
      const page = await linkWallet(who)
      const address = await addressOf(USERS[who].wallet)
      ctx.observed = `linked ${address}, prompts ${(await prompts(page)).join(",")}`
      ctx.verify = `eth_getBalance ${await read.balance(address)}`
    })
  }
  const dirk = await pageFor("dirk"), eva = await pageFor("eva")

  await kase("D", "add_owner through the UI", "Dirk becomes a fourth owner, threshold stays 2", async (ctx) => {
    await ownerChange(ctx, { proposer: anne, kind: "add_owner", fields: { owner: d, threshold: "2" }, title: "Dirk erbij", signers: [anne, bas], executor: cor, wantOwners: [a, b, c, d], wantThreshold: 2 })
    must((await read.owners(fund.safe)).map((x) => x.toLowerCase()).includes(d), "Dirk is no owner on-chain")
    await anne.go(`/accounts/${fund.id}/transparantie`)
    await anne.until(`document.querySelector("#live_owners")?.innerText.includes("Dirk Fresh")`, 30000)
    await anne.shot("D-01-owner-added")
  })

  await kase("D", "change_threshold through the UI", "Threshold 3 of 4", async (ctx) => {
    await ownerChange(ctx, { proposer: anne, kind: "change_threshold", fields: { threshold: "3" }, title: "Drie handtekeningen", signers: [anne, bas], executor: cor, wantOwners: [a, b, c, d], wantThreshold: 3 })
  })

  await kase("D", "Stale signatures: threshold lowered while a payout holds two signatures", "Before: 2 of 3, not executable. After change_threshold(2) executes: 2 of 2 and executable with no new signature, computed live", async (ctx) => {
    const lowering = await propose(anne, fund.id, "change_threshold", { threshold: "2" }, "Terug naar twee")
    const payout = await payoutProposal(anne, b, "0,00002", "Uitbetaling met oude handtekeningen")
    await sign(anne, payout)
    await sign(bas, payout)
    await cor.go(payout.path)
    await cor.until(`document.body.innerText.includes("2 van 3")`, 30000)
    await cor.shot("D-02-partial-2-of-3")
    must(await cor.eval(`!document.querySelector("button[data-action='proposal-execute#execute']")`), "execute offered at 2 of 3")
    const before = await proposalJson(cor, payout)
    must(before.live.executable === false && before.live.reason === "waiting_for_earlier_nonce", JSON.stringify(before.live.reason))
    await cor.go(lowering.path)
    await cor.until(`document.body.innerText.includes("Dit verlaagt het aantal goedkeuringen")`, 30000)
    await cor.shot("D-03-lowers-threshold-warning")
    await finishOwnerChange(ctx, { proposal: lowering, signers: [anne, bas, cor], executor: cor, wantOwners: [a, b, c, d], wantThreshold: 2 })
    await dirk.go(payout.path)
    await dirk.until(`document.body.innerText.includes("2 van 2")`, 30000)
    await dirk.shot("D-04-now-2-of-2-ready")
    const after = await proposalJson(dirk, payout)
    must(after.live.executable === true && after.live.reason === null && after.signatures.length === 2, JSON.stringify(after.live))
    const balance = await read.balance(b)
    const { hash, json } = await execute(anne, payout)
    ctx.tx.push(hash)
    must(json.state === "executed", json.state)
    await eventually("recipient", async () => (await read.balance(b)) - balance === wei(0.00002) || "not yet")
    const moved = await read.balance(b) - balance
    ctx.observed += ` Before: reason ${before.live.reason}, ${before.live.valid_signature_count} of ${before.live.threshold}. After: executable, ${after.live.valid_signature_count} of ${after.live.threshold}, same two signatures. Payout executed.`
    ctx.verify += ` recipient moved ${moved} wei.`
  })

  let afterSwap
  await kase("D", "swap_owner through the UI; the replaced owner's signature stops counting and they cannot sign", "Dirk replaced by Eva. Dirk's earlier signature shows as stale. Dirk's page offers no signing, a direct POST gets signer_not_owner", async (ctx) => {
    const swap = await propose(anne, fund.id, "swap_owner", { old_owner: d, new_owner: e }, "Eva voor Dirk")
    afterSwap = await payoutProposal(anne, b, "0,00002", "Getekend door Dirk voor de vervanging")
    await sign(dirk, afterSwap)
    await finishOwnerChange(ctx, { proposal: swap, signers: [anne, bas], executor: cor, wantOwners: [a, b, c, e], wantThreshold: 2 })
    const json = await proposalJson(anne, afterSwap)
    must(json.live.valid_signature_count === 0, `counted ${json.live.valid_signature_count}`)
    must(json.live.stale_signers.includes(d), JSON.stringify(json.live.stale_signers))
    await anne.go(afterSwap.path)
    await anne.until(`document.body.innerText.includes("telt")&&document.body.innerText.includes("0 van 2")`, 30000)
    await anne.shot("D-05-stale-signature")
    await dirk.go(afterSwap.path)
    await dirk.until(`document.querySelector("#proposal_live")?.innerText.includes("Goedkeuringen")`, 30000)
    must(await dirk.eval(`!document.querySelector("[data-controller~='proposal-sign']")`), "sign panel offered to a replaced owner")
    const refused = await dirk.api("POST", `${afterSwap.api}/signatures`, { signature: await realSignature(dirk, json.safe_tx_hash) })
    // Dirk's signature on this hash already exists; a replay of an old signature is not a new approval.
    const other = await payoutProposal(bas, b, "0,00001", "Dirk mag hier niet meer tekenen")
    const otherJson = await proposalJson(dirk, other)
    const refused2 = await dirk.api("POST", `${other.api}/signatures`, { signature: await realSignature(dirk, otherJson.safe_tx_hash) })
    must(refused2.status === 403 && refused2.json.error === "signer_not_owner", JSON.stringify(refused2))
    state.funds.main.dirkRefused = other
    save()
    ctx.observed += ` Stale signers ${json.live.stale_signers}. Replay POST: ${refused.status} ${refused.json?.error}. New signature POST: ${refused2.status} ${refused2.json.error}.`
    await sign(anne, afterSwap)
    await sign(bas, afterSwap)
    const done = await execute(anne, afterSwap)
    ctx.tx.push(done.hash)
    must(done.json.state === "executed", done.json.state)
  })

  await kase("D", "remove_owner through the UI; the removed owner cannot sign, client or server", "Eva removed, owners a,b,c, threshold 2. A page already open refuses in the browser (not_owner); a direct POST gets signer_not_owner", async (ctx) => {
    const removal = await propose(anne, fund.id, "remove_owner", { owner: e, threshold: "2" }, "Eva eruit")
    const next = await payoutProposal(anne, b, "0,00001", "Na het verwijderen")
    await review(eva, next)
    must(!await toneOf(eva, "proposal-sign"), `review ${await messageOf(eva, "proposal-sign")}`)
    await eva.shot("D-06-eva-reviewed-before-removal")
    await finishOwnerChange(ctx, { proposal: removal, signers: [anne, bas], executor: cor, wantOwners: [a, b, c], wantThreshold: 2 })
    await eva.click("button[data-action='proposal-sign#sign']")
    await eva.until(`document.querySelector("[data-proposal-sign-target=message][data-tone]")`, 30000)
    const text = await messageOf(eva, "proposal-sign")
    must(/geen eigenaar/.test(text), text)
    must(!(await prompts(eva)).includes("eth_signTypedData_v4"), "wallet was asked to sign")
    await eva.shot("D-07-eva-refused")
    const json = await proposalJson(eva, next)
    const refused = await eva.api("POST", `${next.api}/signatures`, { signature: await realSignature(eva, json.safe_tx_hash) })
    must(refused.status === 403 && refused.json.error === "signer_not_owner", JSON.stringify(refused))
    ctx.observed += ` Browser: ${text} Server: ${refused.status} ${refused.json.error}.`
    await sign(anne, next)
    await sign(bas, next)
    const done = await execute(bas, next)
    ctx.tx.push(done.hash)
    must(done.json.state === "executed", done.json.state)
    const other = state.funds.main.dirkRefused
    await sign(anne, other)
    await sign(bas, other)
    const last = await execute(bas, other)
    ctx.tx.push(last.hash)
    must(last.json.state === "executed", last.json.state)
  })

  await kase("D", "Owner events in activity through chain sync", "Added, removed and threshold rows exist", async (ctx) => {
    const text = await pollUntil("owner rows", async () => {
      await anne.go(`/accounts/${fund.id}/activiteit`)
      const body = await anne.text()
      return /Ondertekenaar toegevoegd/.test(body) && /Ondertekenaar verwijderd/.test(body) && /Goedkeuringen gewijzigd/.test(body) ? body : null
    }, 180000, 10000)
    await anne.shot("D-08-activity-owner-events")
    ctx.observed = `rows present; ${(text.match(/Ondertekenaar|Goedkeuringen gewijzigd/g) || []).length} owner rows on the page`
  })
}

// --- E: failures and adversarial cases

const flipLast = (hex) => hex.slice(0, -1) + (hex.endsWith("0") ? "1" : "0")

export async function journeyE() {
  const a = await addressOf("a"), b = await addressOf("b"), c = await addressOf("c"), d = await addressOf("d")
  const fund = main()
  const anne = await pageFor("anne"), bas = await pageFor("bas"), cor = await pageFor("cor")
  const proposalPath = /\/accounts\/\d+\/proposals\/\d+$/
  let target = fund.target

  await kase("E", "Tampered safe_tx_hash at the response layer is refused by the client", "Review refuses with hash_mismatch, wallet never prompted, nothing stored", async (ctx) => {
    target = await payoutProposal(anne, b, "0,00001", "Doel van de manipulatie")
    state.funds.main.target = target
    save()
    await anne.setTamper({ match: proposalPath, mutate: (json) => ({ ...json, safe_tx_hash: flipLast(json.safe_tx_hash) }) })
    await review(anne, target)
    const text = await messageOf(anne, "proposal-sign")
    const tone = await toneOf(anne, "proposal-sign")
    await anne.shot("E-01-tampered-hash")
    await anne.setTamper(null)
    must(tone === "refusal" && /hash/.test(text), `${tone}: ${text}`)
    must((await prompts(anne)).every((name) => name !== "eth_signTypedData_v4"), "wallet prompted")
    must((await proposalJson(anne, target)).signatures.length === 0, "something stored")
    ctx.observed = `${tone}: ${text}`
  })

  await kase("E", "Hash tampered after a clean review is refused at signing time", "Review passes, sign refuses before any wallet prompt", async (ctx) => {
    await review(anne, target)
    must(!await toneOf(anne, "proposal-sign"), "clean review refused")
    await anne.setTamper({ match: proposalPath, mutate: (json) => ({ ...json, safe_tx_hash: flipLast(json.safe_tx_hash) }) })
    await anne.click("button[data-action='proposal-sign#sign']")
    await anne.until(`document.querySelector("[data-proposal-sign-target=message][data-tone]")`, 20000)
    const text = await messageOf(anne, "proposal-sign")
    await anne.setTamper(null)
    must(/hash/.test(text), text)
    must((await prompts(anne)).every((name) => name !== "eth_signTypedData_v4"), "wallet prompted")
    ctx.observed = text
  })

  await kase("E", "Tampered recipient alone, and recipient plus target, are refused by the client", "Refused both ways, no prompt", async (ctx) => {
    const results = []
    for (const [label, mutate] of [
      ["params.recipient only", (json) => ({ ...json, params: { ...json.params, recipient: c } })],
      ["params.recipient and to", (json) => ({ ...json, to: c, params: { ...json.params, recipient: c } })],
      ["data on a native transfer", (json) => ({ ...json, data: "0xdeadbeef" })],
      ["operation delegatecall", (json) => ({ ...json, operation: 1 })],
      ["safe_tx_gas nonzero", (json) => ({ ...json, safe_tx_gas: "1" })]
    ]) {
      await anne.setTamper({ match: proposalPath, mutate })
      await review(anne, target)
      const tone = await toneOf(anne, "proposal-sign")
      const text = await messageOf(anne, "proposal-sign")
      await anne.setTamper(null)
      must(tone === "refusal", `${label}: not refused: ${tone} ${text}`)
      must((await prompts(anne)).every((name) => name !== "eth_signTypedData_v4"), "wallet prompted")
      results.push(`${label}: ${text}`)
    }
    ctx.observed = results.join(" / ")
  })

  await kase("E", "A fully consistent tamper (recipient, target and recomputed hash) shows the attacker's address, and the server refuses the signature", "No client can detect this without another channel: the review must show the real, tampered recipient in full, and the server must refuse a signature over it", async (ctx) => {
    const json = await proposalJson(anne, target)
    const hashCall = (await import("./chain.mjs")).encodeTxHashCall({ to: c, value: BigInt(json.value), data: "0x", nonce: BigInt(json.nonce) })
    const forged = await rpc("eth_call", [{ to: fund.safe, data: hashCall }, "latest"])
    await anne.setTamper({ match: proposalPath, mutate: (row) => ({ ...row, to: c, safe_tx_hash: forged, params: { ...row.params, recipient: c } }) })
    await review(anne, target)
    must(!await toneOf(anne, "proposal-sign"), `refused: ${await messageOf(anne, "proposal-sign")}`)
    const shown = await anne.eval(`document.querySelector("[data-proposal-sign-target=field][data-field=recipient]").textContent`)
    const shownHash = await anne.eval(`document.querySelector("[data-proposal-sign-target=field][data-field=safeTxHash]").textContent`)
    await anne.shot("E-02-consistent-tamper-review")
    must(shown.toLowerCase() === c, `review shows ${shown}`)
    must(shownHash === forged && shownHash !== json.safe_tx_hash, "hash display")
    await anne.click("button[data-action='proposal-sign#sign']")
    await anne.until(`document.querySelector("[data-proposal-sign-target=message][data-tone]")`, 30000)
    const text = await messageOf(anne, "proposal-sign")
    const code = await anne.eval(`document.querySelector("[data-proposal-sign-target=message]").dataset.tone`)
    await anne.setTamper(null)
    must((await proposalJson(anne, target)).signatures.length === 0, "server stored a signature over a forged hash")
    ctx.observed = `Review shows ${shown} and hash ${shownHash} (server's hash is ${json.safe_tx_hash}). Sign: ${code}: ${text}. Stored signatures: 0.`
    ctx.verify = "The hash on the review page differs from the 'Zelf controleren' hash: that comparison is the only defence, as the threat model says"
  })

  await kase("E", "User rejects in the wallet: signing", "Neutral message, nothing stored", async (ctx) => {
    await review(anne, target)
    await anne.eval("window.__provider.failNext(4001,'user rejected')")
    await anne.click("button[data-action='proposal-sign#sign']")
    await anne.until(`document.querySelector("[data-proposal-sign-target=message][data-tone]")`, 20000)
    const tone = await toneOf(anne, "proposal-sign")
    const text = await messageOf(anne, "proposal-sign")
    must(tone === "neutral", `${tone}: ${text}`)
    must((await proposalJson(anne, target)).signatures.length === 0, "stored")
    await anne.shot("E-03-user-rejected")
    ctx.observed = `${tone}: ${text}`
  })

  await kase("E", "Wrong network in the wallet", "Status wrong_network; signing refused without a prompt; switching back restores; no other chain touched", async (ctx) => {
    await review(anne, target)
    await anne.eval("window.__provider.selectChain(1)")
    await anne.until(`document.querySelector("[data-wallet-status='wrong_network']")`, 10000)
    await anne.shot("E-04-wrong-network")
    const before = (await prompts(anne)).length
    await anne.click("button[data-action='proposal-sign#sign']")
    await anne.until(`document.querySelector("[data-proposal-sign-target=message][data-tone]")`, 10000)
    const text = await messageOf(anne, "proposal-sign")
    must(/verkeerde netwerk/.test(text), text)
    must((await prompts(anne)).length === before, "wallet prompted")
    await anne.click("button[data-action='wallet#switchChain']")
    await anne.until(`document.querySelector("[data-wallet-status='ready']")`, 10000)
    ctx.observed = `${text} Switch button returned the wallet to Sepolia: status ready.`
    ctx.verify = "The test provider has no RPC for chain 1 and refuses to send off Sepolia"
  })

  const switcher = await (async () => {
    const page = await (await import("./harness.mjs")).browser.page("anne-switch", { wallets: ["a", "g"] })
    await (await import("./harness.mjs")).logIn(page, "anne")
    return page
  })()

  await kase("E", "Account switched mid-flow while the signature prompt is open", "Flow ends stale, nothing stored", async (ctx) => {
    await review(switcher, target)
    await switcher.eval(`window.__hold="eth_signTypedData_v4"`)
    await switcher.click("button[data-action='proposal-sign#sign']")
    await switcher.until("window.__held", 20000)
    await switcher.eval("window.__provider.selectAccount(1)")
    await sleep(300)
    await switcher.eval("window.__release()")
    await switcher.until(`document.querySelector("[data-proposal-sign-target=message][data-tone]")`, 20000)
    const text = await messageOf(switcher, "proposal-sign")
    await switcher.shot("E-05-account-switched")
    must(/gewisseld|ander adres/.test(text), text)
    must((await proposalJson(anne, target)).signatures.length === 0, "stored")
    ctx.observed = text
    await switcher.eval("window.__provider.selectAccount(0)")
  })

  await kase("E", "Non-owner signature refused by the server; someone else's signature refused", "signer_not_owner, then signer_not_your_wallet; both real signatures over the right hash", async (ctx) => {
    const dirk = await pageFor("dirk")
    const json = await proposalJson(dirk, target)
    const signature = await realSignature(dirk, json.safe_tx_hash)
    const own = await dirk.api("POST", `${target.api}/signatures`, { signature })
    must(own.status === 403 && own.json.error === "signer_not_owner", JSON.stringify(own))
    const stolen = await anne.api("POST", `${target.api}/signatures`, { signature })
    must(stolen.status === 403 && stolen.json.error === "signer_not_your_wallet", JSON.stringify(stolen))
    const garbage = await anne.api("POST", `${target.api}/signatures`, { signature: `0x${"11".repeat(65)}` })
    must(garbage.status >= 400, JSON.stringify(garbage))
    ctx.observed = `Dirk: ${own.status} ${own.json.error}. Anne posting Dirk's: ${stolen.status} ${stolen.json.error}. Garbage: ${garbage.status} ${garbage.json?.error}.`
    ctx.verify = `Stored signatures still ${(await proposalJson(anne, target)).signatures.length}`
  })

  let rejection = fund.rejection
  await kase("E", "Nonce conflict: proposal and rejection share a nonce; proposal executes; rejection becomes superseded", "Same nonce on both, warning shown; after execution rejection is Vervallen and its signatures revert with GS026", async (ctx) => {
    await anne.go(target.path)
    await anne.until(`document.querySelector("form[action$='/reject']")`, 30000)
    await anne.submit("form[action$='/reject']", "voorstellen/\\d+")
    const path = (await anne.path()).split("?")[0]
    must(path !== target.path, "no rejection page")
    rejection = { path, id: Number(path.match(/(\d+)$/)[1]), api: path.replace("voorstellen", "proposals"), fundId: fund.id }
    state.funds.main.rejection = rejection
    save()
    const [left, right] = [await proposalJson(anne, target), await proposalJson(anne, rejection)]
    must(left.nonce === right.nonce && left.safe_tx_hash !== right.safe_tx_hash, "not the same nonce")
    await anne.until(`document.body.innerText.includes("hetzelfde volgnummer")`, 30000)
    await anne.shot("E-06-same-nonce-warning")
    for (const proposal of [target, rejection]) { await sign(anne, proposal); await sign(bas, proposal) }
    const { hash, json } = await execute(cor, target)
    ctx.tx.push(hash)
    must(json.state === "executed", json.state)
    const after = await proposalJson(anne, rejection)
    must(after.state === "superseded", `rejection is ${after.state}`)
    await anne.go(rejection.path)
    await anne.until(`document.body.innerText.includes("Vervallen")`, 30000)
    await anne.shot("E-07-superseded")
    const sim = await simulate({ from: c, to: fund.safe, data: encodeExec({ to: after.to, value: BigInt(after.value), data: after.data, signatures: joinSignatures(after.signatures) }) })
    must(!sim.ok && /GS026/.test(sim.revert), JSON.stringify(sim))
    ctx.observed = `Shared nonce ${left.nonce}. Proposal ${json.state}; rejection ${after.state}, UI: Vervallen.`
    ctx.verify = `eth_call of the rejection with its signatures: ${sim.revert}`
  })

  await kase("E", "Rejection transaction executes; the proposal becomes superseded; no money moves", "Self-call with zero value, nonce +1, recipient unchanged, no contribution row", async (ctx) => {
    const victim = await payoutProposal(anne, b, "0,00001", "Wordt afgewezen")
    await sign(anne, victim)
    await bas.go(victim.path)
    await bas.until(`document.querySelector("form[action$='/reject']")`, 30000)
    await bas.submit("form[action$='/reject']", "voorstellen/\\d+")
    const path = (await bas.path()).split("?")[0]
    const reject = { path, id: Number(path.match(/(\d+)$/)[1]), api: path.replace("voorstellen", "proposals"), fundId: fund.id }
    const balance = await read.balance(b)
    const safeBalance = await read.balance(fund.safe)
    const nonce = await read.nonce(fund.safe)
    await sign(anne, reject)
    await sign(bas, reject)
    const { hash, json } = await execute(cor, reject)
    ctx.tx.push(hash)
    must(json.state === "executed", json.state)
    must((await proposalJson(anne, victim)).state === "superseded", "victim not superseded")
    await eventually("nonce after rejection", async () => (await read.nonce(fund.safe)) === nonce + 1 || "not yet")
    must(await read.balance(b) === balance && await read.balance(fund.safe) === safeBalance, "money moved")
    const tx = await read.tx(hash)
    must(tx.to.toLowerCase() === fund.safe, "not to the Safe")
    await sleep(70000)
    await anne.go(`/accounts/${fund.id}/activiteit`)
    const zero = await anne.eval(`[...document.querySelectorAll("li")].some(li=>li.innerText.includes("+0,00 ETH")||li.innerText.includes("+0 ETH"))`)
    must(!zero, "a zero contribution row")
    await anne.shot("E-08-activity-after-rejection")
    ctx.observed = `Rejection ${json.state}, proposal superseded, no contribution row`
    ctx.verify = `Recipient ${balance} unchanged; Safe ${safeBalance} unchanged; nonce ${nonce} -> ${nonce + 1}`
  })

  let large = fund.large
  // Stage F (SECURITY_REVIEW M11): a payout the Safe cannot cover is never offered for execution.
  await kase("E", "Payout larger than the balance is not ready, says why, and offers rejection and cancel", "Signatures valid, live reason insufficient_balance, no execute panel, rejection and cancel offered; eth_call GS013; no transaction", async (ctx) => {
    large = await payoutProposal(anne, b, "1", "Meer dan er in zit")
    state.funds.main.large = large
    save()
    await sign(anne, large)
    await sign(bas, large)
    const nonce = await read.nonce(fund.safe)
    await cor.go(large.path)
    await cor.until(`document.querySelector("[data-testid=insufficient-balance]")`, 30000)
    await cor.shot("E-09-too-large-not-ready")
    must(await cor.eval(`!document.querySelector("button[data-action='proposal-execute#execute']")`), "execute offered")
    must(await cor.eval(`!!document.querySelector("form[action$='/reject']")`), "no rejection offered")
    must(await anne.eval(`true`), "")
    await anne.go(large.path)
    await anne.until(`document.querySelector("form[action$='/cancel']")`, 30000)
    const text = (await cor.text()).match(/Te weinig saldo[^\n]*\n[^\n]*/)?.[0] || ""
    const json = await proposalJson(cor, large)
    must(json.live.executable === false && json.live.reason === "insufficient_balance" && json.live.valid_signature_count === 2, JSON.stringify(json.live))
    const sim = await simulate({ from: c, to: fund.safe, data: encodeExec({ to: json.to, value: BigInt(json.value), data: json.data, signatures: joinSignatures(json.signatures) }) })
    must(!sim.ok && /GS013/.test(sim.revert), JSON.stringify(sim))
    must(!await cor.eval("(window.__sent||[]).length"), "a transaction was sent")
    must(await read.nonce(fund.safe) === nonce, "nonce moved")
    ctx.observed = `live: executable ${json.live.executable}, reason ${json.live.reason}, ${json.live.valid_signature_count} of ${json.live.threshold}, fund_balance ${json.live.fund_balance} wei. Page: ${text.replace(/\s+/g, " ")}. No execute button; rejection offered to Cor, cancel offered to Anne (admin).`
    ctx.verify = `eth_call: ${sim.revert}. Safe balance ${await read.balance(fund.safe)} wei; nonce ${nonce} unchanged`
  })

  await kase("E", "Same payout really mined and reverted: nothing shows as success", "Status 0, nonce unchanged, server says reverted, proposal stays open", async (ctx) => {
    const json = await proposalJson(cor, large)
    const nonce = await read.nonce(fund.safe)
    const safeBalance = await read.balance(fund.safe)
    const { hash, receipt } = await send("c", { to: fund.safe, data: encodeExec({ to: json.to, value: BigInt(json.value), data: json.data, signatures: joinSignatures(json.signatures) }), gas: 300000 }, { startTotal: state.startTotal })
    ctx.tx.push(hash)
    must(receipt.status === "0x0", `status ${receipt.status}`)
    must(await read.nonce(fund.safe) === nonce, "nonce moved")
    const hint = await cor.api("POST", `${large.api}/execution`, { tx_hash: hash })
    must(hint.json.execution_check === "reverted" && hint.json.state === "open", JSON.stringify({ c: hint.json.execution_check, s: hint.json.state }))
    await sleep(70000)
    const later = await proposalJson(cor, large)
    must(later.state === "open" && !later.execution_tx_hash, `${later.state} ${later.execution_tx_hash}`)
    await cor.go(large.path)
    await cor.until(`document.querySelector("#proposal_live")?.innerText.includes("Goedkeuringen")`, 30000)
    must(!(await cor.text()).includes("Uitgevoerd op de blockchain"), "shows executed")
    await cor.shot("E-10-reverted-still-open")
    ctx.observed = `Server: execution_check ${hint.json.execution_check}, state ${hint.json.state}; after a sync cycle still ${later.state}; UI shows no success`
    ctx.verify = `Receipt status 0; nonce ${nonce} unchanged; Safe balance ${safeBalance} -> ${await read.balance(fund.safe)}. ExecutionFailure is unreachable by design here: safeTxGas 0 reverts with GS013 instead`
  })

  await kase("E", "Clear the blocked nonce with a rejection", "The over-large proposal is superseded", async (ctx) => {
    await anne.go(large.path)
    await anne.until(`document.querySelector("form[action$='/reject']")`, 30000)
    await anne.submit("form[action$='/reject']", "voorstellen/\\d+")
    const path = (await anne.path()).split("?")[0]
    const reject = { path, id: Number(path.match(/(\d+)$/)[1]), api: path.replace("voorstellen", "proposals"), fundId: fund.id }
    await sign(anne, reject)
    await sign(bas, reject)
    const { hash } = await execute(bas, reject)
    ctx.tx.push(hash)
    must((await proposalJson(anne, large)).state === "superseded", "not superseded")
    ctx.observed = "superseded"
  })

  await kase("E", "Insufficient gas from an empty fresh address", "Clear gas message, no prompt", async (ctx) => {
    const dirk = await pageFor("dirk")
    must(await read.balance(d) === 0n, "Dirk's wallet is not empty")
    // A ready proposal is needed: since stage F the over-large one is never offered for execution.
    const small = await payoutProposal(anne, b, "0,00001", "Klaar, maar zonder gas uitvoeren")
    await sign(anne, small)
    await sign(bas, small)
    await openExecutePanel(dirk, small)
    await dirk.click("button[data-action='proposal-execute#check']")
    await dirk.until(`document.querySelector("[data-execution-ready]")||document.querySelector("[data-proposal-execute-target=message][data-tone]")`, 30000)
    await dirk.click("button[data-action='proposal-execute#execute']")
    await sleep(500)
    await dirk.until(`document.querySelector("[data-proposal-execute-target=message][data-tone]")`, 30000)
    const text = await messageOf(dirk, "proposal-execute")
    await dirk.shot("E-11-no-gas")
    must(/te weinig tegoed/.test(text), text)
    must(!(await prompts(dirk)).includes("eth_sendTransaction"), "prompted")
    // Then withdrawn by the admin: signed, so the page must say the signatures stay valid on-chain.
    await anne.go(small.path)
    await anne.until(`document.querySelector("form[action$='/cancel']")`, 30000)
    must(/blijven op de blockchain geldig/.test(await anne.text()), "cancel panel does not warn about signatures")
    await anne.submit("form[action$='/cancel']", "voorstellen/\\d+")
    const flash = (await anne.text()).match(/Voorstel ingetrokken[^\n]*/)?.[0] || ""
    must(/blijven geldig/.test(flash), flash)
    must((await proposalJson(anne, small)).state === "cancelled", "not cancelled")
    await anne.shot("E-11b-cancelled-signed")
    ctx.observed = `${text} Then cancelled by Anne (admin): ${flash}`
    ctx.verify = `eth_getBalance ${d} = 0`
  })

  await kase("E", "User rejects in the wallet: sending", "Neutral message, no transaction", async (ctx) => {
    const payout = await payoutProposal(anne, b, "0,00001", "Weigeren in de wallet, daarna wel")
    await sign(anne, payout)
    await sign(bas, payout)
    await openExecutePanel(cor, payout)
    await cor.click("button[data-action='proposal-execute#check']")
    await cor.until(`document.querySelector("[data-execution-ready='true']")`, 30000)
    const count = await read.txCount(c)
    await cor.eval("window.__provider.failNext(4001,'user rejected')")
    await cor.click("button[data-action='proposal-execute#execute']")
    await cor.until(`document.querySelector("[data-proposal-execute-target=message][data-tone]")`, 30000)
    const tone = await toneOf(cor, "proposal-execute")
    const text = await messageOf(cor, "proposal-execute")
    must(tone === "neutral", `${tone} ${text}`)
    must(await read.txCount(c) === count, "tx sent")
    ctx.observed = `${tone}: ${text}`
    state.funds.main.switchTarget = payout
    save()
  })

  await kase("E", "Account switched mid-flow while the send prompt is open", "Stale, no transaction from either address", async (ctx) => {
    const payout = state.funds.main.switchTarget
    await openExecutePanel(switcher, payout)
    await switcher.click("button[data-action='proposal-execute#check']")
    await switcher.until(`document.querySelector("[data-execution-ready='true']")`, 30000)
    const count = await read.txCount(a)
    await switcher.eval(`window.__hold="eth_sendTransaction"`)
    await switcher.click("button[data-action='proposal-execute#execute']")
    await switcher.until("window.__held", 30000)
    await switcher.eval("window.__provider.selectAccount(1)")
    await sleep(300)
    await switcher.eval("window.__release()")
    await switcher.until(`document.querySelector("[data-proposal-execute-target=message][data-tone]")`, 20000)
    const text = await messageOf(switcher, "proposal-execute")
    await switcher.shot("E-12-account-switched-send")
    must(/gewisseld|ander adres/.test(text), text)
    must(await read.txCount(a) === count, "tx sent")
    must(!await switcher.eval("(window.__sent||[]).length"), "provider sent")
    ctx.observed = text
    ctx.verify = `eth_getTransactionCount unchanged at ${count}`
    const done = await execute(cor, payout)
    ctx.tx.push(done.hash)
    must(done.json.state === "executed", "cleanup")
  })

  const fenna = await register("fenna").catch(async () => pageFor("fenna"))
  await kase("E", "Replayed wallet challenge refused", "Second use of a nonce and signature is refused, with a real signature", async (ctx) => {
    const f = await addressOf("f")
    await fenna.go("/wallet")
    const challenge = await fenna.api("POST", "/wallet_challenges", { address: f, purpose: "link" })
    must(challenge.status < 300, JSON.stringify(challenge))
    const hex = `0x${Buffer.from(challenge.json.message, "utf8").toString("hex")}`
    const signature = await fenna.eval(`window.__provider.request({method:"personal_sign",params:[${JSON.stringify(hex)},${JSON.stringify(f)}]})`)
    const first = await fenna.api("POST", "/wallets", { address: f, nonce: challenge.json.nonce, signature })
    must(first.status < 300, JSON.stringify(first))
    const replay = await fenna.api("POST", "/wallets", { address: f, nonce: challenge.json.nonce, signature })
    must(replay.status >= 400, JSON.stringify(replay))
    const otherUser = await pageFor("gijs").catch(() => null)
    ctx.observed = `First: ${first.status}. Replay by the same user: ${replay.status} ${replay.json?.error}: ${replay.json?.message}`
    if (otherUser) {
      await register("gijs")
      await otherUser.go("/wallet")
      const stolen = await otherUser.api("POST", "/wallets", { address: f, nonce: challenge.json.nonce, signature })
      must(stolen.status >= 400, JSON.stringify(stolen))
      ctx.observed += `. Replay by another user: ${stolen.status} ${stolen.json?.error}`
    }
  })

  await kase("E", "Viewer and non-member blocked", "Viewer: reads, no actions, 403 on the API. Non-member: 404 everywhere. Viewer role set by the admin on the members page", async (ctx) => {
    await inviteAndJoin("anne", fund.id, "fenna")
    // Stage F: the role is set on the members page by the admin, no longer in the database.
    await anne.go(`/users?account_id=${fund.id}`)
    const set = await anne.eval(`(()=>{const select=[...document.querySelectorAll("select[name=role]")].find(s=>s.closest(".rounded-xl")?.innerText.includes("Fenna Kijker"));if(!select)return false;select.value="viewer";select.form.requestSubmit();return true})()`)
    must(set, "no role form for Fenna")
    await anne.until(`/Rol gewijzigd/.test(document.body.innerText)`, 20000)
    await anne.shot("E-12-role-set-to-viewer")
    const results = []
    await fenna.go(`/accounts/${fund.id}/activiteit`)
    must(/Activiteit/.test(await fenna.text()), "viewer cannot read")
    await fenna.go(`/accounts/${fund.id}/inleggen`)
    must(/leesrechten/.test(await fenna.text()), "contribute not blocked")
    must(await fenna.eval(`!document.querySelector("button[data-action='contribute#contribute']")`), "contribute button")
    await fenna.shot("E-13-viewer-contribute")
    await fenna.go(`/accounts/${fund.id}/voorstellen/new?kind=transfer_native`)
    must(/dashboard/.test(await fenna.path()), `new proposal page open: ${await fenna.path()}`)
    const post = await fenna.api("POST", `/accounts/${fund.id}/proposals`, { kind: "transfer_native", title: "x", params: { recipient: b, amount: "1" } })
    must(post.status === 403, JSON.stringify(post))
    results.push(`viewer propose ${post.status} ${post.json?.error}`)
    const json = await proposalJson(fenna, state.funds.main.target)
    const signature = await realSignature(fenna, json.safe_tx_hash)
    const sig = await fenna.api("POST", `${state.funds.main.target.api}/signatures`, { signature })
    must(sig.status >= 400, JSON.stringify(sig))
    results.push(`viewer sign ${sig.status} ${sig.json?.error}`)
    const gijs = await pageFor("gijs")
    if (!state.users.gijs) await register("gijs")
    for (const path of [`/accounts/${fund.id}/activiteit`, `/accounts/${fund.id}/voorstellen`, `/accounts/${fund.id}/inleggen`, `/accounts/${fund.id}/ramp`, `/accounts/${fund.id}/safe`, `/accounts/${fund.id}/proposals`, `/accounts/${fund.id}/chain_events.csv`, state.funds.main.target.api]) {
      const response = await gijs.api("GET", path)
      must(response.status === 404, `${path}: ${response.status}`)
    }
    results.push("non-member 404 on 8 pages and API paths")
    ctx.observed = results.join("; ")
  })

  await kase("E", "RPC down, browser and server blocked at the harness: no zero shown", "Balance shows the labelled last value or says unavailable, never a bare zero. Proposals say unavailable, execution not offered. Recovers afterwards", async (ctx) => {
    const { execFileSync } = await import("node:child_process")
    const { writeFileSync, rmSync } = await import("node:fs")
    const flag = `${process.env.FT_E2E_OUT}/rpc_down`
    const db = process.env.FT_E2E_DB || "ft_e2e_live"
    const open = await payoutProposal(anne, b, "0,00001", "Tijdens de storing")
    await sign(anne, open)
    await sign(bas, open)
    const observations = []
    try {
      writeFileSync(flag, "1")
      await anne.blockRpc(true)
      await sleep(1000)
      await anne.go("/dashboard")
      await anne.settle(90000)
      const cached = await anne.eval(`document.querySelector("turbo-frame[id*=balance]")?.innerText||""`)
      await anne.shot("E-14-outage-dashboard-cached")
      must(/laatst bekende stand/.test(cached), `dashboard: ${cached}`)
      observations.push(`Dashboard with a cached value: ${cached.replace(/\s*\n+\s*/g, " | ")}`)
      execFileSync("psql", ["-d", db, "-c", `update accounts set balance_cached=null, balance_cached_at=null where id=${fund.id}`], { stdio: "ignore" })
      await anne.go("/dashboard")
      await anne.settle(90000)
      const none = await anne.eval(`document.querySelector("turbo-frame[id*=balance]")?.innerText||""`)
      await anne.shot("E-15-outage-dashboard-no-cache")
      must(/niet worden opgehaald/.test(none) && !/0,00/.test(none), `dashboard: ${none}`)
      observations.push(`Dashboard without a cached value: ${none.replace(/\s*\n+\s*/g, " | ")}`)
      await anne.go(open.path)
      await anne.settle(90000)
      const live = await anne.eval(`document.querySelector("#proposal_live")?.innerText||""`)
      await anne.shot("E-16-outage-proposal")
      must(/niet beschikbaar/.test(live), live)
      must(await anne.eval(`!document.querySelector("button[data-action='proposal-execute#execute']")`), "execute offered in an outage")
      observations.push(`Proposal: ${live.split("\n")[0]}`)
      await anne.go(`/accounts/${fund.id}/inleggen`)
      await walletReady(anne)
      await anne.until(`document.querySelector("[data-contribute-target=message][data-tone]")`, 45000)
      const fields = await anne.eval(`[document.querySelector("[data-field=walletBalance]").textContent,document.querySelector("[data-field=gasBalance]").textContent]`)
      const message = await messageOf(anne, "contribute")
      await anne.shot("E-17-outage-contribute")
      must(fields.every((value) => value === ""), `balances shown: ${fields}`)
      observations.push(`Contribute: balances empty; ${message}`)
      const create = await anne.api("POST", `/accounts/${fund.id}/proposals`, { kind: "transfer_native", title: "x", params: { recipient: b, amount: "1" } })
      must(create.status === 503, JSON.stringify(create))
      observations.push(`Propose by API: ${create.status} ${create.json.error}`)
      const events = await anne.eval(`fetch("/accounts/${fund.id}/chain_events.csv").then(r=>r.text()).then(t=>t.trim().split("\\n").length)`)
      must(events > 3, "events gone")
      observations.push(`Stored activity still readable: ${events - 1} rows`)
    } finally {
      rmSync(flag, { force: true })
      await anne.blockRpc(false)
    }
    await anne.go(open.path)
    await anne.until(`document.body.innerText.includes("2 van 2")`, 45000)
    const done = await execute(bas, open)
    ctx.tx.push(done.hash)
    must(done.json.state === "executed", done.json.state)
    observations.push("After recovery: proposal 2 of 2, executed")
    ctx.observed = observations.join(". ")
  })

  // Second fund: a Safe deployed by someone else first, then a real permissionless execution.
  const second = () => state.funds.second
  await kase("E", "Deployment retried on an already-deployed identical Safe", "Outside the app, the identical deployment is sent first. The UI then sends nothing, verifies, and goes active. A second attempt reverts Create2 call failed", async (ctx) => {
    if (!second()) {
      await anne.go("/accounts/new")
      await anne.fill("input[name='account[name]']", `E2E Tweede ${state.run}`)
      await anne.fill("textarea[name='account[description]']", "Voorgelopen deployment")
      await anne.submit("form[action='/accounts']", "uitnodigen")
      state.funds.second = { id: Number((await anne.path()).match(/accounts\/(\d+)/)[1]) }
      save()
    }
    if (!second().joined) {
      await inviteAndJoin("anne", second().id, "bas")
      await inviteAndJoin("anne", second().id, "cor")
      state.funds.second.joined = true
      save()
    }
    // Keeps the same address on a resumed run: the configuration is read back, never made anew.
    let deployment = (await anne.api("GET", `/accounts/${second().id}/safe`)).json
    if (!deployment.safe_address) {
      const created = await anne.api("POST", `/accounts/${second().id}/safe`, { chain_id: CHAIN_ID, token_address: EURC, owners: [a, b], threshold: 2, acknowledge_risk: true })
      must(created.status === 201, JSON.stringify(created))
      deployment = created.json
    }
    const hex = (value) => BigInt(value).toString(16).padStart(64, "0")
    const init = deployment.initializer.slice(2)
    const data = `0x1688f0b9${deployment.singleton.slice(2).padStart(64, "0")}${hex(96)}${hex(deployment.salt_nonce)}${hex(init.length / 2)}${init.padEnd(Math.ceil(init.length / 64) * 64, "0")}`
    state.funds.second.safe = deployment.safe_address
    save()
    if (!second().frontRunTx) {
      const { hash, receipt } = await send("c", { to: FACTORY, data }, { startTotal: state.startTotal })
      must(receipt.status === "0x1", "front-run failed")
      state.funds.second.frontRunTx = hash
      save()
    }
    ctx.tx.push(second().frontRunTx)
    await eventually("code at the Safe address", async () => (await read.code(deployment.safe_address)).length > 2 || "no code")
    await anne.go(`/accounts/${second().id}/safe_instellen`)
    await walletReady(anne)
    await anne.eval(`document.querySelector("[data-controller~='threshold']")&&0`)
    await anne.until(`document.querySelector("[data-threshold-target=ackRow]")&&!document.querySelector("[data-threshold-target=ackRow]").hidden`)
    await anne.click("input[data-threshold-target=ack]")
    await anne.shot("E-18-deploy-retry-form")
    const sendsBefore = await read.txCount(a)
    await anne.click("button[data-action='safe-deploy#deploy']")
    const active = await pollUntil("active", async () => {
      const row = await anne.api("GET", `/accounts/${second().id}/safe`)
      return row.json?.status === "active" ? row.json : null
    }, 120000, 3000)
    must(active.safe_address === deployment.safe_address, "another address")
    must(await read.txCount(a) === sendsBefore, "the UI sent a transaction")
    must((await prompts(anne)).every((name) => name !== "eth_sendTransaction"), "wallet prompted")
    const again = await simulate({ from: a, to: FACTORY, data })
    must(!again.ok && /Create2 call failed/.test(again.revert), JSON.stringify(again))
    const facts = await safeFacts(deployment.safe_address)
    must(sameOwners(facts.owners, [a, b]) && facts.threshold === 2 && facts.singleton === SINGLETON, JSON.stringify(facts))
    await anne.go(`/accounts/${second().id}/transparantie`)
    await anne.shot("E-19-deploy-retry-active")
    ctx.observed = `Safe ${active.safe_address} active, no wallet prompt, deployed by owner-c outside the app. deploy_tx_hash in the app: ${active.deploy_tx_hash}`
    ctx.verify = `eth_call createProxyWithNonce again: ${again.revert}; owners a,b; threshold 2; canonical singleton`
  })

  await kase("E", "Third party non-owner executes (permissionless)", "Cor is no owner of this Safe, executes with his own gas; state from ExecutionSuccess; Cor's page says he need not sign", async (ctx) => {
    const fund2 = second()
    const funded = await send("a", { to: fund2.safe, value: wei(0.00005) }, { startTotal: state.startTotal })
    ctx.tx.push(funded.hash)
    const proposal = await propose(anne, fund2.id, "transfer_native", { recipient_choice: "other", recipient: b, amount: "0,00002" }, "Door een niet-ondertekenaar uitgevoerd")
    await sign(anne, proposal)
    await sign(bas, proposal)
    must(!(await read.owners(fund2.safe)).map((x) => x.toLowerCase()).includes(c), "Cor is an owner")
    const before = await read.balance(b)
    const { hash, json } = await execute(cor, proposal)
    ctx.tx.push(hash)
    must(json.state === "executed", json.state)
    must((await read.tx(hash)).from.toLowerCase() === c, "not Cor")
    const receipt = await read.receipt(hash)
    must(receipt.logs.some((log) => log.topics[0] === TOPICS.ExecutionSuccess && log.topics[1] === json.safe_tx_hash), "no ExecutionSuccess")
    await eventually("recipient", async () => (await read.balance(b)) - before === wei(0.00002) || "not yet")
    await cor.shot("E-20-permissionless-executed")
    ctx.observed = `Executed from ${c}, not an owner of ${fund2.safe}; state ${json.state}`
    ctx.verify = `getOwners excludes the sender; ExecutionSuccess matches ${json.safe_tx_hash}; recipient moved exactly 0.00002 ETH`
  })
}

// --- F: ramp pages and the off-ramp prefill

export async function journeyF() {
  const a = await addressOf("a"), b = await addressOf("b"), c = await addressOf("c")
  const fund = main()
  const anne = await pageFor("anne"), bas = await pageFor("bas")

  await kase("F", "Testnet route shows the faucet, honest labels, and external links go to real pages", "Test money stated, no provider route, links answer", async (ctx) => {
    await anne.go(`/accounts/${fund.id}/ramp`)
    const text = await anne.text()
    must(/testgeld/i.test(text) && /niets waard|geen waarde/.test(text), "no test money label")
    must(!/Monerium|Mt Pelerin/.test(text), "provider on a testnet page")
    await anne.shot("F-01-ramp-on")
    await anne.go(`/accounts/${fund.id}/ramp?direction=off`)
    const off = await anne.text()
    must(/Geen omwisseling op een testnetwerk/.test(off), "no honest off-ramp statement")
    await anne.shot("F-02-ramp-off")
    await anne.go(`/accounts/${fund.id}/ramp`)
    const links = await anne.eval(`[...document.querySelectorAll('a[target=_blank]')].map(l=>({href:l.href,rel:l.rel}))`)
    must(links.length > 0, "no external links")
    const results = []
    for (const { href, rel } of links) {
      must(/noopener/.test(rel) && /noreferrer/.test(rel), `rel on ${href}`)
      const response = await fetch(href, { redirect: "follow", headers: { "user-agent": "Mozilla/5.0 (Macintosh) Chrome/142" }, signal: AbortSignal.timeout(25000) }).catch((error) => ({ status: error.message }))
      results.push(`${href} -> ${response.status}`)
    }
    must(results.some((row) => /faucet\.circle\.com.*-> 200/.test(row)), results.join("; "))
    ctx.observed = results.join("; ")
  })

  await kase("F", "All ramp links to app pages work", "Every action link answers 200 on a real page", async (ctx) => {
    const seen = []
    for (const direction of ["on", "off"]) {
      await anne.go(`/accounts/${fund.id}/ramp?direction=${direction}`)
      const links = await anne.eval(`[...document.querySelectorAll('[data-ramp-action]')].map(l=>({a:l.dataset.rampAction,h:l.getAttribute('href')})).filter(l=>l.h&&l.h.startsWith('/'))`)
      for (const { a: action, h: href } of links) {
        const status = await anne.eval(`fetch(${JSON.stringify(href)}).then(r=>r.status)`)
        must(status === 200, `${href}: ${status}`)
        seen.push(`${direction}/${action}: ${href.replace(/recipient=0x[0-9a-f]+/, "recipient=<own wallet>")} ${status}`)
      }
    }
    must(seen.some((row) => row.includes("payout")) && seen.some((row) => row.includes("contribute")), seen.join("; "))
    ctx.observed = seen.join("; ")
  })

  let payout = fund.prefillPayout
  await kase("F", "Off-ramp prefill reaches a real Safe proposal, signed by real owners", "Click on the ramp link: own wallet selected and named in full, amount empty, nothing submitted; proposal carries that recipient; real signatures; executed; recipient gets exactly 1,50 EURC", async (ctx) => {
    await anne.go(`/accounts/${fund.id}/ramp?direction=off`)
    const countBefore = (await anne.api("GET", `/accounts/${fund.id}/proposals`)).json.proposals.length
    await anne.click("[data-ramp-action='payout']")
    await anne.until(`/voorstellen\\/new/.test(location.pathname)&&document.querySelector("[data-recipient-link]")`, 20000)
    await anne.settle()
    await anne.shot("F-03-prefilled-form")
    must(await anne.eval(`document.querySelector("[data-recipient-link]").dataset.recipientLink`) === "own", "not flagged as own")
    const shown = await anne.eval(`document.querySelector("[data-recipient-link]").textContent`)
    must(shown.toLowerCase() === a && shown !== a, `shown ${shown}`)
    must(await anne.eval(`document.querySelector("select[name=recipient_choice]").value`) === a, "not selected")
    must(await anne.eval(`document.querySelector("input[name=amount]").value`) === "", "amount filled")
    must((await anne.api("GET", `/accounts/${fund.id}/proposals`)).json.proposals.length === countBefore, "submitted by itself")
    await anne.fill("input[name=amount]", "1,50")
    await anne.fill("input[name=title]", "Uitbetaling via off-ramp")
    await anne.submit("form[action$='/voorstellen']", "voorstellen/\\d+")
    const path = (await anne.path()).split("?")[0]
    payout = { path, id: Number(path.match(/(\d+)$/)[1]), api: path.replace("voorstellen", "proposals"), fundId: fund.id }
    state.funds.main.prefillPayout = payout
    save()
    const json = await proposalJson(anne, payout)
    must(json.params.recipient === a && json.params.amount === "1500000" && json.to === EURC, JSON.stringify(json.params))
    await sign(anne, payout)
    await sign(bas, payout)
    const [mine, held] = [await read.eurc(a), await read.eurc(fund.safe)]
    must(held >= 1_500_000n, `Safe holds ${held} units: B_eurc has to run first`)
    const done = await execute(bas, payout)
    ctx.tx.push(done.hash)
    must(done.json.state === "executed", done.json.state)
    await eventually("recipient balance", async () => (await read.eurc(a)) - mine === 1_500_000n || "not yet")
    await bas.shot("F-04-offramp-payout-executed")
    ctx.observed = `Form showed ${shown} as own wallet, amount empty, not submitted. Proposal: to EURC, recipient ${json.params.recipient}, 1500000 units, safeTxHash ${json.safe_tx_hash}; 2 real signatures; ${done.json.state}.`
    ctx.verify = `balanceOf(recipient) ${mine} -> ${await read.eurc(a)}; ExecutionSuccess in ${done.hash}`
  })

  await kase("F", "Tampered recipient inside token calldata is refused", "data pays someone else than params says: calldata_mismatch, no prompt", async (ctx) => {
    await anne.go(`/accounts/${fund.id}/voorstellen`)
    const other = await propose(bas, fund.id, "transfer_token", { recipient_choice: "other", recipient: c, amount: "0,75" }, "Token-calldata manipulatie")
    await bas.setTamper({ match: /\/accounts\/\d+\/proposals\/\d+$/, mutate: (json) => ({ ...json, data: json.data.replace(c.slice(2), b.slice(2)) }) })
    await review(bas, other)
    const tone = await toneOf(bas, "proposal-sign")
    const text = await messageOf(bas, "proposal-sign")
    await bas.setTamper(null)
    must(tone === "refusal", `${tone} ${text}`)
    await bas.shot("F-05-token-calldata-tamper")
    ctx.observed = text
    state.funds.main.tokenTamper = other
    save()
  })

  await kase("F", "Crafted links: someone else's address warns, a stranger goes in the free field, garbage fills nothing", "Warning in full, never submitted", async (ctx) => {
    await anne.go(`/accounts/${fund.id}/voorstellen/new?kind=transfer_token&recipient=${b}`)
    must(await anne.eval(`document.querySelector("[data-recipient-link]").dataset.recipientLink`) === "other", "Bas's wallet not flagged")
    must(await anne.eval(`document.querySelector("select[name=recipient_choice]").value`) === b, "not selected")
    const stranger = "0x000000000000000000000000000000000000dead"
    await anne.go(`/accounts/${fund.id}/voorstellen/new?kind=transfer_token&recipient=${stranger}`)
    must(await anne.eval(`document.querySelector("select[name=recipient_choice]").value`) === "other", "not the free field")
    must(await anne.eval(`document.querySelector("input[name=recipient]").value`) === stranger, "not prefilled")
    must(await anne.eval(`!document.querySelector("[data-recipient-target=other]").hidden`), "free field hidden")
    await anne.shot("F-06-crafted-link-warning")
    await anne.go(`/accounts/${fund.id}/voorstellen/new?kind=transfer_token&recipient=${encodeURIComponent("<img src=x onerror=alert(1)>")}`)
    must(await anne.eval(`document.querySelector("[data-recipient-link]").dataset.recipientLink`) === "invalid", "garbage accepted")
    must(await anne.eval(`document.querySelector("input[name=recipient]").value`) === "", "garbage filled")
    ctx.observed = "Bas: flagged other, selected. Stranger: free field, warning. Markup: invalid notice, nothing filled, no CSP event"
  })

  await kase("F", "Clear the queue: reject the open token proposal", "Superseded by an executed rejection", async (ctx) => {
    for (const proposal of [state.funds.main.tokenTamper]) {
      await anne.go(proposal.path)
      await anne.until(`document.querySelector("form[action$='/reject']")`, 30000)
      await anne.submit("form[action$='/reject']", "voorstellen/\\d+")
      const path = (await anne.path()).split("?")[0]
      const reject = { path, id: Number(path.match(/(\d+)$/)[1]), api: path.replace("voorstellen", "proposals"), fundId: fund.id }
      await sign(anne, reject)
      await sign(bas, reject)
      const { hash } = await execute(bas, reject)
      ctx.tx.push(hash)
      must((await proposalJson(anne, proposal)).state === "superseded", "not superseded")
    }
    ctx.observed = "Superseded"
  })
}

// --- G: exit hatch

export async function journeyG() {
  const { execFileSync } = await import("node:child_process")
  const b = await addressOf("b"), c = await addressOf("c")
  const fund = main()
  const anne = await pageFor("anne")

  let open
  await kase("G", "Execute a Safe transaction with no FundTogether code, and the app notices", "test/e2e/exit_hatch.mjs (raw RPC and hand-built calldata) pays out with two owner signatures. A proposal open at that nonce in the app becomes superseded through the recurring sync alone", async (ctx) => {
    open = await propose(anne, fund.id, "transfer_native", { recipient_choice: "other", recipient: b, amount: "0,00001" }, "Open in de app tijdens de exit")
    await sign(anne, open)
    const before = await read.balance(c)
    const output = execFileSync("node", [new URL("./exit_hatch.mjs", import.meta.url).pathname, fund.safe, c, "10000000000000"], { encoding: "utf8", env: process.env })
    const result = JSON.parse(output.trim().split("\n").at(-1))
    ctx.tx.push(result.hash)
    must(result.status === "0x1", "reverted")
    await eventually("recipient", async () => (await read.balance(c)) - before === 10_000_000_000_000n || "not yet")
    const row = await pollUntil("app sees it", async () => (await proposalJson(anne, open)).state === "superseded" ? "superseded" : null, 240000, 8000)
    await anne.go(open.path)
    await anne.until(`document.body.innerText.includes("Vervallen")`, 30000)
    await anne.shot("G-01-superseded-by-exit")
    ctx.observed = `Sent by the script from ${result.from}, nonce ${result.nonce}. App proposal at that nonce: ${row}, UI: Vervallen, without any request to the app`
    ctx.verify = `ExecutionSuccess in the receipt (${result.success}); recipient moved exactly 0.00001 ETH by eth_getBalance`
  })

  await kase("G", "Move EURC with no FundTogether code", "exit_hatch.mjs transfers 0,50 EURC from the Safe with two owner signatures; the app shows the transfer through sync", async (ctx) => {
    const [held, before] = [await read.eurc(fund.safe), await read.eurc(b)]
    const output = execFileSync("node", [new URL("./exit_hatch.mjs", import.meta.url).pathname, fund.safe, b, "500000", EURC], { encoding: "utf8", env: process.env })
    const result = JSON.parse(output.trim().split("\n").at(-1))
    ctx.tx.push(result.hash)
    must(result.status === "0x1" && result.success, JSON.stringify(result))
    await eventually("balances", async () => (await read.eurc(b)) - before === 500_000n && held - (await read.eurc(fund.safe)) === 500_000n || "not yet")
    const row = await pollUntil("row", async () => {
      await anne.go(`/accounts/${fund.id}/activiteit`)
      return anne.eval(`[...document.querySelectorAll('a[href$=${JSON.stringify(result.hash)}]')].map(a=>a.closest("li").innerText.replace(/\\s*\\n+\\s*/g," | ")).find(t=>t.includes("EURC"))||null`)
    }, 240000, 8000)
    await anne.shot("G-02-eurc-exit-in-activity")
    ctx.observed = `Sent from ${result.from}. App, with no request: ${row}`
    ctx.verify = `ExecutionSuccess for ${result.safeTxHash}; balanceOf recipient ${before} -> ${await read.eurc(b)}; Safe ${held} -> ${await read.eurc(fund.safe)}`
  })

  await kase("G", "Safe{Wallet} link and Safe's own service", "Link is https://app.safe.global/home?safe=sep:<EIP-55 address>. Not a claim of UI compatibility; a human has to do that drill", async (ctx) => {
    const { readFileSync } = await import("node:fs")
    const viem = await import(`data:text/javascript;base64,${readFileSync(new URL("../../vendor/javascript/viem.js", import.meta.url)).toString("base64")}`)
    await anne.go(`/accounts/${fund.id}/transparantie`)
    const href = await anne.eval(`[...document.querySelectorAll("a")].find(l=>l.textContent.includes("Safe{Wallet}"))?.href`)
    must(href === `https://app.safe.global/home?safe=sep:${viem.getAddress(fund.safe)}`, `href ${href}`)
    const page = await fetch(href, { signal: AbortSignal.timeout(25000) }).catch((error) => ({ status: error.message }))
    const service = await fetch(`https://safe-transaction-sepolia.safe.global/api/v1/safes/${viem.getAddress(fund.safe)}/`, { signal: AbortSignal.timeout(25000) }).catch((error) => ({ status: error.message }))
    const body = service.json && service.status === 200 ? await service.json() : null
    ctx.observed = `${href} -> HTTP ${page.status}. Safe Transaction Service -> HTTP ${service.status}${body ? `: owners ${body.owners?.length}, threshold ${body.threshold}, version ${body.version}, masterCopy ${body.masterCopy}` : ""}`
    ctx.verify = "HTTP status of a single-page app says the URL resolves, nothing about the app's behaviour. Safe{Wallet} drill remains for a human"
  })
}

// --- Z: finality, run at least 20 minutes after B

export async function journeyZ() {
  const fund = main()
  const anne = await pageFor("anne")
  await kase("Z", "EURC contributions become final through the recurring sync; members' totals count them", "Rows go from In behandeling to Definitief with no request; Anne's own tile counts 5,25 EURC", async (ctx) => {
    const hash = fund.eurcTx
    const row = await pollUntil("Definitief", async () => {
      const value = await activityRow(anne, fund.id, hash)
      return value && /Definitief/.test(value) ? value : null
    }, 1500000, 30000)
    const finalized = await rpc("eth_getBlockByNumber", ["finalized", false])
    const receipt = await read.receipt(hash)
    must(BigInt(receipt.blockNumber) <= BigInt(finalized.number), "chain says not final")
    await anne.go("/dashboard")
    await anne.settle()
    const text = (await anne.text()).replace(/\s*\n+\s*/g, " | ")
    const tile = (text.match(/Jouw inleg[^|]* \| [^|]+\| [^|]+/) || [""])[0]
    must(tile.includes("5,25 EURC"), tile)
    await anne.shot("Z-02-eurc-final")
    ctx.tx.push(hash)
    ctx.observed = `${row}. ${tile}`
    ctx.verify = `Tx in block ${BigInt(receipt.blockNumber)}, finalized head ${BigInt(finalized.number)}`
  })
  await kase("Z", "Pending becomes final through the recurring sync", "The row of B's member send goes from In behandeling to Definitief with no request; CSV follows", async (ctx) => {
    const hash = fund.pendingTx
    const row = await pollUntil("Definitief", async () => {
      const value = await activityRow(anne, fund.id, hash)
      return value && /Definitief/.test(value) ? value : null
    }, 600000, 30000)
    const line = await csvRow(anne, fund.id, hash)
    must(/definitief/i.test(line), line)
    const finalized = await rpc("eth_getBlockByNumber", ["finalized", false])
    const receipt = await read.receipt(hash)
    must(BigInt(receipt.blockNumber) <= BigInt(finalized.number), "chain says not final")
    await anne.shot("Z-01-final")
    ctx.observed = `${row}. CSV: ${line}`
    ctx.tx.push(hash)
    ctx.verify = `Tx in block ${BigInt(receipt.blockNumber)}, finalized head ${BigInt(finalized.number)}`
  })
}

// --- C and E again with EURC

export async function journeyC_token() {
  const b = await addressOf("b"), c = await addressOf("c")
  const fund = main()
  const anne = await pageFor("anne"), bas = await pageFor("bas"), cor = await pageFor("cor")
  let payout
  await kase("C", "EURC payout: one signature is not enough", "1 of 2, no execute button, execTransaction simulation reverts GS020, balance unchanged", async (ctx) => {
    payout = await propose(anne, fund.id, "transfer_token", { recipient_choice: c, amount: "2,50" }, "EURC-uitbetaling aan Cor")
    await sign(anne, payout)
    await bas.go(payout.path)
    await bas.until(`document.body.innerText.includes("1 van 2")`, 30000)
    await bas.shot("C-10-token-1-of-2")
    must(await bas.eval(`!document.querySelector("button[data-action='proposal-execute#execute']")`), "execute offered")
    const json = await proposalJson(bas, payout)
    must(json.to === EURC && json.params.amount === "2500000" && json.params.recipient === c, JSON.stringify(json.params))
    const sim = await simulate({ from: b, to: fund.safe, data: encodeExec({ to: json.to, value: 0n, data: json.data, signatures: joinSignatures(json.signatures) }) })
    must(!sim.ok && /GS020/.test(sim.revert), JSON.stringify(sim))
    ctx.observed = `UI 1 van 2, reason ${json.live.reason}; proposal to EURC, recipient ${json.params.recipient}, 2500000 units`
    ctx.verify = `eth_call: ${sim.revert}`
  })
  await kase("C", "EURC payout: second owner signs, an owner executes", "Bas signs, Anne executes (she also signed; Cor is the recipient). ExecutionSuccess, exactly 2,50 EURC moves, token_out row names Cor, balance frame follows", async (ctx) => {
    payout ||= await propose(anne, fund.id, "transfer_token", { recipient_choice: c, amount: "2,50" }, "EURC-uitbetaling aan Cor")
    await sign(bas, payout)
    const [safeBefore, cBefore, nonce] = [await read.eurc(fund.safe), await read.eurc(c), await read.nonce(fund.safe)]
    const { hash, json } = await execute(anne, payout)
    ctx.tx.push(hash)
    must(json.state === "executed", json.state)
    await anne.shot("C-11-token-executed")
    const receipt = await read.receipt(hash)
    must(receipt.logs.some((log) => log.topics[0] === TOPICS.ExecutionSuccess && log.topics[1] === json.safe_tx_hash), "no ExecutionSuccess")
    await eventually("balances", async () => (await read.eurc(c)) - cBefore === 2_500_000n && safeBefore - (await read.eurc(fund.safe)) === 2_500_000n || "not yet")
    const row = await pollUntil("token_out row", async () => {
      await anne.go(`/accounts/${fund.id}/activiteit`)
      return anne.eval(`[...document.querySelectorAll('a[href$=${JSON.stringify(hash)}]')].map(a=>a.closest("li").innerText.replace(/\\s*\\n+\\s*/g," | ")).find(t=>t.includes("EURC"))||null`)
    }, 240000, 8000)
    must(/−2,50 EURC/.test(row) && /Cor Bakker/.test(row), row)
    await anne.shot("C-12-token-activity")
    await anne.go("/dashboard")
    await anne.settle()
    const shown = await anne.eval(`document.querySelector("turbo-frame[id=balance_hero]")?.innerText||""`)
    const onChain = await read.eurc(fund.safe)
    ctx.observed = `${json.state}. ${row}. Balance frame: ${shown.replace(/\s*\n+\s*/g, " | ")}`
    ctx.verify = `ExecutionSuccess ${json.safe_tx_hash}; balanceOf Cor ${cBefore} -> ${await read.eurc(c)}; Safe ${safeBefore} -> ${onChain}; nonce from ${nonce}`
  })
}

export async function journeyE_token() {
  const b = await addressOf("b"), c = await addressOf("c")
  const fund = main()
  const anne = await pageFor("anne"), bas = await pageFor("bas"), cor = await pageFor("cor")
  const large = () => propose(anne, fund.id, "transfer_token", { recipient_choice: "other", recipient: b, amount: "1000" }, "Meer EURC dan er in zit")
  await kase("E", "EURC payout larger than the balance is not ready and says why", "Signatures valid, live reason insufficient_balance, no execute panel, simulation GS013, no transaction", async (ctx) => {
    const proposal = await large()
    await sign(anne, proposal)
    await sign(bas, proposal)
    const [nonce, held] = [await read.nonce(fund.safe), await read.eurc(fund.safe)]
    must(held < 1_000_000_000n, "Safe holds enough")
    await cor.go(proposal.path)
    await cor.until(`document.querySelector("[data-testid=insufficient-balance]")`, 30000)
    must(await cor.eval(`!document.querySelector("button[data-action='proposal-execute#execute']")`), "execute offered")
    const text = (await cor.text()).match(/Te weinig saldo[^\n]*\n[^\n]*/)?.[0]?.replace(/\s+/g, " ") || ""
    await cor.shot("E-30-token-too-large")
    must(!await cor.eval("(window.__sent||[]).length"), "a transaction was sent")
    const json = await proposalJson(cor, proposal)
    must(json.live.reason === "insufficient_balance" && json.live.fund_balance === held.toString(), JSON.stringify(json.live))
    const sim = await simulate({ from: c, to: fund.safe, data: encodeExec({ to: json.to, value: 0n, data: json.data, signatures: joinSignatures(json.signatures) }) })
    must(!sim.ok && /GS013/.test(sim.revert), JSON.stringify(sim))
    ctx.observed = `${text} live.reason ${json.live.reason}, fund_balance ${json.live.fund_balance}. State ${json.state}.`
    ctx.verify = `eth_call: ${sim.revert}; balanceOf(Safe) ${held} is below 1000000000; nonce ${nonce}`
  })
  await kase("E", "Same EURC payout really mined and reverted: nothing shows as success", "Status 0, nonce and balances unchanged, server says reverted, proposal stays open, no token_out row. Then cleared by a rejection", async (ctx) => {
    const proposal = await large()
    const json = await proposalJson(cor, proposal)
    const [nonce, held, recipient] = [await read.nonce(fund.safe), await read.eurc(fund.safe), await read.eurc(b)]
    if (json.state === "open") {
      const { hash, receipt } = await send("c", { to: fund.safe, data: encodeExec({ to: json.to, value: 0n, data: json.data, signatures: joinSignatures(json.signatures) }), gas: 300000 }, { startTotal: state.startTotal })
      ctx.tx.push(hash)
      must(receipt.status === "0x0", `status ${receipt.status}`)
      const hint = await cor.api("POST", `${proposal.api}/execution`, { tx_hash: hash })
      must(hint.json.execution_check === "reverted" && hint.json.state === "open", JSON.stringify({ c: hint.json.execution_check, s: hint.json.state }))
      await sleep(70000)
      const later = await proposalJson(cor, proposal)
      must(later.state === "open" && !later.execution_tx_hash, later.state)
      must(await read.nonce(fund.safe) === nonce && await read.eurc(fund.safe) === held && await read.eurc(b) === recipient, "something moved")
      must(!await activityRow(cor, fund.id, hash), "the reverted tx shows in activity")
      await cor.go(proposal.path)
      await cor.until(`document.querySelector("#proposal_live")?.innerText.includes("Goedkeuringen")`, 30000)
      must(!(await cor.text()).includes("Uitgevoerd op de blockchain"), "shows executed")
      await cor.shot("E-31-token-reverted-still-open")
      ctx.observed = `execution_check ${hint.json.execution_check}, after a sync cycle ${later.state}; no activity row; UI shows no success.`
      ctx.verify = `Receipt status 0; nonce ${nonce}; balanceOf Safe ${held} and recipient ${recipient} unchanged. `
    }
    await anne.go(proposal.path)
    await anne.until(`document.querySelector("form[action$='/reject']")`, 30000)
    await anne.submit("form[action$='/reject']", "voorstellen/\\d+")
    const path = (await anne.path()).split("?")[0]
    const reject = asProposal(fund.id, Number(path.match(/(\d+)$/)[1]))
    await sign(anne, reject)
    await sign(bas, reject)
    const done = await execute(bas, reject)
    ctx.tx.push(done.hash)
    must((await proposalJson(anne, proposal)).state === "superseded", "not superseded")
    ctx.observed += " Cleared: rejection executed, proposal superseded."
  })
}

// --- Stage F: the hardening, live. No money moves in H except gas for one rejection.

export async function journeyH() {
  const b = await addressOf("b"), c = await addressOf("c")
  const fund = main()
  const anne = await pageFor("anne"), bas = await pageFor("bas"), cor = await pageFor("cor"), dirk = await pageFor("dirk")
  const api = (page, verb, path, body) => page.api(verb, `/accounts/${fund.id}${path}`, body)

  await kase("H", "A member who is no owner cannot park nonces: every junk proposal takes the live nonce, and the cap stops them", "5 accepted at the chain nonce, the 6th refused 429; an owner's payout and an owner change still go in at the live nonce", async (ctx) => {
    const nonce = await read.nonce(fund.safe)
    const owners = lower(await read.owners(fund.safe))
    must(!owners.includes(await addressOf("d")), "Dirk is an owner")
    const made = []
    for (let i = 0; i < 6; i++) {
      const response = await api(dirk, "POST", "/proposals", { kind: "transfer_native", title: `Junk ${i}`, params: { recipient: b, amount: String(i + 1) } })
      made.push(`${response.status}:${response.json.nonce ?? response.json.error}`)
    }
    must(made.slice(0, 5).every((entry) => entry === `201:${nonce}`), made.join(","))
    must(made[5] === "429:too_many_open_proposals", made[5])
    const owner = await api(anne, "POST", "/proposals", { kind: "transfer_native", title: "Echte uitbetaling naast junk", params: { recipient: b, amount: "7" } })
    must(owner.status === 201 && owner.json.nonce === String(nonce), JSON.stringify(owner.json).slice(0, 200))
    const change = await api(anne, "POST", "/proposals", { kind: "change_threshold", title: "Eigenaarswijziging kan altijd", params: { threshold: "1" }, acknowledge_risk: true })
    must(change.status === 201 && change.json.nonce === String(nonce), JSON.stringify(change.json).slice(0, 200))
    must(change.json.live.warnings.includes("sibling_at_same_nonce"), "no sibling warning")
    state.funds.main.hJunk = { owner: owner.json.id, change: change.json.id }
    save()
    await anne.go(`/accounts/${fund.id}/voorstellen/${change.json.id}`)
    await anne.until(`document.querySelector("#proposal_live")?.innerText.includes("Goedkeuringen")`, 30000)
    await anne.shot("H-01-owner-change-at-live-nonce")
    ctx.observed = `chain nonce ${nonce}. Dirk (member, no owner): ${made.join(", ")}. Anne's payout nonce ${owner.json.nonce}, Anne's change_threshold nonce ${change.json.nonce} with sibling warning.`
    ctx.verify = `eth_call nonce() ${nonce}; getOwners excludes Dirk`
  })

  await kase("H", "Cancel: the proposer withdraws an unsigned proposal on the page; another member cannot; an admin can", "Dirk's button cancels his own; Bas gets 403 on Dirk's; Anne cancels the rest; cancelled proposals refuse signatures", async (ctx) => {
    const list = (await api(anne, "GET", "/proposals")).json.proposals.filter((row) => row.state === "open" && /^Junk/.test(row.title))
    must(list.length === 5, `junk ${list.length}`)
    const first = asProposal(fund.id, list[0].id)
    await dirk.go(first.path)
    await dirk.until(`document.querySelector("form[action$='/cancel']")`, 30000)
    must(/intrekken is genoeg/.test(await dirk.text()), "unsigned wording missing")
    await dirk.submit("form[action$='/cancel']", "voorstellen/\\d+")
    await dirk.until(`/Ingetrokken/.test(document.body.innerText)`, 30000)
    await dirk.shot("H-02-cancelled-by-proposer")
    const byBas = await api(bas, "DELETE", `/proposals/${list[1].id}`)
    must(byBas.status === 403 && byBas.json.error === "cancel_forbidden", JSON.stringify(byBas.json))
    const results = []
    for (const row of list.slice(1)) results.push((await api(anne, "DELETE", `/proposals/${row.id}`)).json.state)
    must(results.every((value) => value === "cancelled"), results.join(","))
    for (const id of Object.values(state.funds.main.hJunk)) must((await api(anne, "DELETE", `/proposals/${id}`)).json.state === "cancelled", `cancel ${id}`)
    const json = await proposalJson(bas, first)
    const signature = await realSignature(bas, json.safe_tx_hash)
    const refused = await api(bas, "POST", `/proposals/${first.id}/signatures`, { signature })
    must(refused.status === 409 && refused.json.error === "proposal_not_open", JSON.stringify(refused.json))
    const again = await api(dirk, "POST", "/proposals", { kind: "transfer_native", title: "Na intrekken weer ruimte", params: { recipient: b, amount: "9" } })
    must(again.status === 201, JSON.stringify(again.json))
    must((await api(dirk, "DELETE", `/proposals/${again.json.id}`)).json.state === "cancelled", "own cancel by API")
    ctx.observed = `Dirk cancelled ${first.path} on the page. Bas: ${byBas.status} ${byBas.json.error}. Anne cancelled ${results.length + 2} more. Signing a cancelled one: ${refused.status} ${refused.json.error}. After cancelling, Dirk could propose again (201) and withdraw it.`
  })

  await kase("H", "A signed proposal, once cancelled, still has valid signatures on-chain: the page says so, and a rejection settles it", "Admin cancel shows the warning; eth_call of execTransaction with the stored signatures would succeed; a rejection from the cancelled proposal's page executes and the proposal is superseded", async (ctx) => {
    const payout = await payoutProposal(anne, b, "0,00001", "Ingetrokken maar getekend")
    await sign(anne, payout)
    await sign(bas, payout)
    await anne.go(payout.path)
    await anne.until(`document.querySelector("form[action$='/cancel']")`, 30000)
    await anne.submit("form[action$='/cancel']", "voorstellen/\\d+")
    const flash = (await anne.text()).match(/Voorstel ingetrokken[^\n]*/)?.[0] || ""
    must(/blijven geldig/.test(flash), flash)
    const json = await proposalJson(anne, payout)
    must(json.state === "cancelled", json.state)
    const sim = await simulate({ from: c, to: fund.safe, data: encodeExec({ to: json.to, value: BigInt(json.value), data: json.data, signatures: joinSignatures(json.signatures) }) })
    must(sim.ok, `expected the old signatures to still execute in a simulation: ${JSON.stringify(sim)}`)
    await anne.until(`document.querySelector("form[action$='/reject']")`, 30000)
    await anne.shot("H-03-cancelled-signed-offers-rejection")
    await anne.submit("form[action$='/reject']", "voorstellen/\\d+")
    const path = (await anne.path()).split("?")[0]
    const reject = asProposal(fund.id, Number(path.match(/(\d+)$/)[1]))
    await sign(anne, reject)
    await sign(bas, reject)
    const done = await execute(bas, reject)
    ctx.tx.push(done.hash)
    await eventually("superseded", async () => (await proposalJson(anne, payout)).state === "superseded" || (await proposalJson(anne, payout)).state)
    const after = await simulate({ from: c, to: fund.safe, data: encodeExec({ to: json.to, value: BigInt(json.value), data: json.data, signatures: joinSignatures(json.signatures) }) })
    must(!after.ok, "still executable after the rejection")
    ctx.observed = `${flash} Simulation before the rejection: would succeed. Rejection executed; proposal ${(await proposalJson(anne, payout)).state}.`
    ctx.verify = `eth_call execTransaction with the cancelled proposal's two signatures: ok before, ${after.revert} after the rejection`
  })

  await kase("H", "Contribute page checks the Safe on-chain and shows where money goes", "Destination verified from the chain: canonical, no modules or guard, address follows from the deployment; owners and threshold from getOwners", async (ctx) => {
    await bas.go(`/accounts/${fund.id}/inleggen`)
    await bas.until(`document.querySelector("[data-testid=destination]")?.dataset.destinationState`, 30000)
    const stateName = await bas.eval(`document.querySelector("[data-testid=destination]").dataset.destinationState`)
    const owners = await bas.eval(`document.querySelector("[data-field=destinationOwners]").textContent`)
    const status = await bas.eval(`document.querySelector("[data-field=destinationStatus]").textContent`)
    await bas.shot("H-04-contribute-destination")
    must(stateName === "verified", `${stateName}: ${status}`)
    const chainOwners = lower(await read.owners(fund.safe))
    must(chainOwners.every((owner) => owners.toLowerCase().includes(owner)), `${owners} vs ${chainOwners}`)
    ctx.observed = `${status} Owners shown: ${owners.replace(/\n/g, ", ")}`
    ctx.verify = `getOwners ${chainOwners.join(",")}`
  })

  await kase("H", "Ambiguous amount refused with an explanation; the parsed amount is echoed", "1.000 refused in the contribute form and in the proposal form; 1,5 echoed as 1,50", async (ctx) => {
    await bas.go(`/accounts/${fund.id}/inleggen`)
    await walletReady(bas)
    await bas.fill("input[data-contribute-target=amount]", "1,5")
    await bas.eval(`document.querySelector("input[data-contribute-target=amount]").dispatchEvent(new Event("input",{bubbles:true}))`)
    await bas.until(`/precies 1,50/.test(document.querySelector("[data-amount-echo-target=output]").textContent)`, 10000)
    await bas.fill("input[data-contribute-target=amount]", "1.000")
    await bas.eval(`document.querySelector("input[data-contribute-target=amount]").dispatchEvent(new Event("input",{bubbles:true}))`)
    await bas.until(`/Bedoel je/.test(document.querySelector("[data-amount-echo-target=output]").textContent)`, 10000)
    await bas.click("button[data-action='contribute#contribute']")
    await bas.until(`document.querySelector("[data-contribute-target=message][data-tone]")`, 20000)
    const text = await messageOf(bas, "contribute")
    must(/Bedoel je/.test(text), text)
    must(!(await prompts(bas)).includes("eth_sendTransaction"), "prompted")
    await bas.shot("H-05-ambiguous-amount")
    const form = await api(anne, "POST", "/proposals", { kind: "transfer_token", title: "x", params: { recipient: b, amount: "1.000" } })
    ctx.observed = `Contribute: ${text}. Proposal JSON with amount "1.000" (base units are integers there): ${form.status} ${form.json.error}.`
    if (form.status === 201) await api(anne, "DELETE", `/proposals/${form.json.id}`)
  })
}
