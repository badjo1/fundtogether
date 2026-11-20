// Shared by the journeys: state between runs, evidence, users and the UI steps of a proposal.
import { appendFileSync, existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs"
import { Browser, sleep } from "./browser.mjs"
import { ROOT, addressOf, assertBudget, explorerTx, secrets, totalFunded } from "./chain.mjs"

export { sleep }
const OUT = process.env.FT_E2E_OUT
if (!OUT) throw new Error("set FT_E2E_OUT to a directory outside the repo")
if (!process.env.FT_E2E_SCREENS) process.env.FT_E2E_SCREENS = `${OUT}/screens`
export const BASE = `http://localhost:${process.env.FT_E2E_PORT || 3458}`
export const PASSWORD = "e2e-wachtwoord-123"
const STATE = `${OUT}/state.json`
const EVIDENCE = `${OUT}/evidence.jsonl`

export const state = existsSync(STATE) ? JSON.parse(readFileSync(STATE, "utf8")) : { run: Date.now().toString(36), users: {}, funds: {}, proposals: {}, done: {} }
export const save = () => writeFileSync(STATE, JSON.stringify(state, null, 1))

// Nothing this harness prints or stores may contain a key, whatever an error message picks up.
export function scrub(text) {
  let out = String(text)
  for (const secret of secrets()) out = out.split(secret).join("[REDACTED]")
  return out
}
export const say = (...parts) => console.log(scrub(parts.join(" ")))

export const browser = new Browser({ out: OUT, base: BASE })
export async function start() {
  await browser.start()
  if (!state.startTotal) { state.startTotal = (await totalFunded()).toString(); save() }
}
export async function budget() { return assertBudget(state.startTotal) }

// One case of a journey. Records what happened. A thrown error is a FAIL with its message.
export async function kase(journey, name, expected, work, { once = true } = {}) {
  const id = `${journey}: ${name}`
  if (once && state.done[id] === "PASS") { say(`skip ${id}`); return }
  const ctx = { tx: [], observed: "", verify: "", result: "PASS" }
  const started = Date.now()
  // Every case is bounded: a stall fails with its own message instead of hanging the run (2026-11-09 18:03).
  const limit = Number(process.env.FT_E2E_CASE_TIMEOUT_MS || 1_800_000)
  let timer
  try {
    await Promise.race([work(ctx), new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`case timed out after ${limit} ms`)), limit) })])
  } catch (error) {
    ctx.result = "FAIL"
    ctx.observed = `${ctx.observed} ERROR: ${error.message}`.trim()
    for (const [who, page] of Object.entries(pages)) await page.shot(`FAIL-${journey}-${Date.now()}-${who}`).catch(() => {})
  } finally {
    clearTimeout(timer)
  }
  const row = { at: new Date().toISOString(), journey, case: name, expected, observed: ctx.observed, tx: ctx.tx, explorer: ctx.tx.map(explorerTx), verify: ctx.verify, result: ctx.result, ms: Date.now() - started }
  appendFileSync(EVIDENCE, `${scrub(JSON.stringify(row))}\n`)
  state.done[id] = ctx.result
  save()
  say(`${ctx.result.padEnd(7)} ${id}`, ctx.observed ? `\n        observed: ${ctx.observed}` : "", ctx.tx.length ? `\n        tx: ${ctx.tx.join(" ")}` : "", ctx.verify ? `\n        verify: ${ctx.verify}` : "")
  return ctx
}

export function notRun(journey, name, expected, reason) {
  const row = { at: new Date().toISOString(), journey, case: name, expected, observed: reason, tx: [], explorer: [], verify: "", result: "NOT RUN" }
  appendFileSync(EVIDENCE, `${scrub(JSON.stringify(row))}\n`)
  say(`NOT RUN ${journey}: ${name}\n        ${reason}`)
}

export function must(condition, message) { if (!condition) throw new Error(message) }

// --- Users

const pages = {}
export const USERS = {
  anne: { name: "Anne de Vries", wallet: "a" }, bas: { name: "Bas Jansen", wallet: "b" }, cor: { name: "Cor Bakker", wallet: "c" },
  dirk: { name: "Dirk Fresh", wallet: "d" }, eva: { name: "Eva Fresh", wallet: "e" }, fenna: { name: "Fenna Kijker", wallet: "f" }, gijs: { name: "Gijs Buitenstaander", wallet: null }
}
export const emailOf = (who) => `${who}.${state.run}@example.com`

export async function pageFor(who, { extraWallets = [] } = {}) {
  if (pages[who]) return pages[who]
  const wallet = USERS[who].wallet
  pages[who] = await browser.page(who, { wallets: wallet ? [wallet, ...extraWallets] : [] })
  if (state.users[who]) await logIn(pages[who], who)
  return pages[who]
}

// The app allows 10 logins per 3 minutes per address. A limited login lands on /session/new: wait it out, never assume.
export async function logIn(page, who) {
  for (let attempt = 0; attempt < 6; attempt++) {
    await page.go("/login")
    await page.fill("input[name=email_address]", emailOf(who))
    await page.fill("input[name=password]", PASSWORD)
    await page.eval(`document.querySelector("form[action='/login']").requestSubmit()`)
    await page.until(`!/^\\/login$/.test(location.pathname)||document.querySelector("[role=alert]")`, 20000).catch(() => {})
    await sleep(500)
    if (!/\/login|\/session/.test(await page.path())) return
    await sleep(45000)
  }
  throw new Error(`login failed for ${who}`)
}

export async function fillRegistration(page, who) {
  const since = Date.now() - 1000
  await page.fill("input[name='user[name]']", USERS[who].name)
  await page.fill("input[name='user[email_address]']", emailOf(who))
  await page.eval(`document.querySelectorAll("input[type=password]").forEach(e=>{e.value=${JSON.stringify(PASSWORD)}})`)
  await page.submit("form[action='/register']")
  state.users[who] = { email: emailOf(who) }
  save()
  return since
}

// Stage F: an address is confirmed through the real mail, in the same logged-in browser (one click, no password).
export async function confirmEmail(page, who, since) {
  const link = await mailLink(emailOf(who), since, /https?:\/\/[^"'\s<]+\/email_bevestigen\/[^"'\s<&]+/)
  await page.go(new URL(link).pathname)
  await page.until(`[...document.querySelectorAll("button")].some(x=>/Bevestigen/.test(x.textContent))`)
  must(await page.eval(`!document.querySelector("input[name=password]")`), "own session still asked for a password")
  await page.clickText("button", "Bevestigen")
  await page.until(`/dashboard|accounts\\/new|invitations/.test(location.pathname)`, 20000)
  state.users[who].confirmed = true
  save()
  return link
}

export async function register(who) {
  const page = await pageFor(who)
  if (state.users[who]) return page
  await page.go("/register")
  const since = await fillRegistration(page, who)
  await page.until(`!/register/.test(location.pathname)`, 20000)
  await confirmEmail(page, who, since)
  return page
}

// The real mail, as delivered by the real job. letter_opener writes it to tmp/letter_opener.
export async function invitationMail(to, since, ms = 60000) {
  return mailLink(to, since, /https?:\/\/[^"'\s<]+\/invitations\/[^"'\s<]+\/open/, ms)
}

export async function mailLink(to, since, pattern, ms = 60000) {
  const dir = `${ROOT}/tmp/letter_opener`
  const end = Date.now() + ms
  while (Date.now() < end) {
    if (existsSync(dir)) {
      // Only mail written after this invitation was made: a member can hold older, spent invitations.
      const folders = readdirSync(dir).map((name) => `${dir}/${name}`).filter((path) => statSync(path).isDirectory() && statSync(path).mtimeMs >= since)
      for (const folder of folders) {
        const file = `${folder}/rich.html`
        if (!existsSync(file)) continue
        const html = readFileSync(file, "utf8")
        const link = html.match(pattern)
        if (link && html.includes(to)) return link[0].replace(/&amp;/g, "&")
      }
    }
    await sleep(1000)
  }
  throw new Error(`no mail for ${to} matching ${pattern} after ${ms} ms: is Solid Queue running?`)
}

// Invited by mail, then a new user: mail link, accept, register, joined.
export async function inviteAndJoin(admin, fundId, who) {
  const adminPage = await pageFor(admin)
  const since = Date.now() - 1000
  await adminPage.go(`/accounts/${fundId}/uitnodigen`)
  await adminPage.fill("input[name='invitation[email]']", emailOf(who))
  await adminPage.submit("form[action='/invitations']", "invitations/success")
  const link = await invitationMail(emailOf(who), since)
  const page = await pageFor(who)
  await page.go(link)
  await page.until(`[...document.querySelectorAll("button,input[type=submit]")].some(x=>/Accepteer/.test(x.textContent+x.value))`)
  await page.clickText("button,input[type=submit]", "Accepteer")
  if (state.users[who]) {
    await page.until(`/dashboard/.test(location.pathname)`, 20000)
  } else {
    await page.until(`/register/.test(location.pathname)`, 20000)
    const prefilled = await page.eval(`document.querySelector("input[name='user[email_address]']").value`)
    must(prefilled === emailOf(who), `registration not prefilled with the invited address: ${prefilled}`)
    const since = await fillRegistration(page, who)
    // Stage F: an addressed invitation joins only after the address is confirmed.
    await page.until(`/email_bevestigen/.test(location.pathname)`, 20000)
    must(!/Je bent toegevoegd/.test(await page.text()), "joined before confirming")
    await confirmEmail(page, who, since)
    await page.until(`/dashboard/.test(location.pathname)`, 20000)
  }
  return { page, link }
}

export async function walletReady(page, status = "ready") {
  await page.until(`document.querySelector("[data-wallet-status='${status}']")||document.querySelector("[data-wallet-key-param]")`, 20000)
  if (await page.eval(`!document.querySelector("[data-wallet-status='${status}']")`)) {
    await page.click("button[data-wallet-key-param]")
    await page.until(`document.querySelector("[data-wallet-status='${status}']")`, 20000)
  }
}

export async function linkWallet(who) {
  const page = await pageFor(who)
  await page.go("/wallet")
  await page.until(`document.querySelector("[data-wallet-key-param]")||document.querySelector("[data-wallet-status='unlinked']")||document.querySelector("[data-wallet-status='address_mismatch']")`)
  if (await page.eval(`!!document.querySelector("[data-wallet-key-param]")&&!document.querySelector("[data-wallet-status='unlinked']")&&!document.querySelector("[data-wallet-status='address_mismatch']")`)) {
    await page.click("button[data-wallet-key-param]")
    await page.until(`document.querySelector("[data-wallet-status='unlinked']")||document.querySelector("[data-wallet-status='address_mismatch']")`)
  }
  await page.click("button[data-action='wallet-link#link']")
  await page.until(`document.querySelector("li[data-controller='modal']")||document.querySelector("[data-wallet-link-target=message][data-tone]")`, 30000)
  const tone = await page.eval(`document.querySelector("[data-wallet-link-target=message]")?.dataset.tone||""`)
  must(!tone, `link: ${await page.eval(`document.querySelector("[data-wallet-link-target=message]")?.textContent`)}`)
  const wallets = await page.api("GET", "/wallets")
  const address = await addressOf(USERS[who].wallet)
  must(wallets.json.wallets.some((row) => row.address === address), "wallet not listed by the server after linking")
  return page
}

// --- Proposals through the UI

export const messageOf = (page, flow) => page.eval(`document.querySelector("[data-${flow}-target=message]")?.textContent||""`)
export const toneOf = (page, flow) => page.eval(`document.querySelector("[data-${flow}-target=message]")?.dataset.tone||""`)
export const stateOf = (page, flow) => page.eval(`document.querySelector("[data-controller~='${flow}']")?.dataset.flowState||""`)
export const prompts = (page) => page.eval("(window.__prompts||[]).slice()")

// Runs resume after a failure: a proposal with this title that still stands is reused, a signature already given
// is not given twice, an executed proposal is not executed twice. Nothing about its outcome is assumed.
export function asProposal(fundId, id) {
  const path = `/accounts/${fundId}/voorstellen/${id}`
  return { path, id, api: `/accounts/${fundId}/proposals/${id}`, fundId }
}

export async function propose(page, fundId, kind, fields, title) {
  const existing = (await page.api("GET", `/accounts/${fundId}/proposals`)).json?.proposals?.find((row) => row.title === title && !["superseded", "cancelled"].includes(row.state))
  if (existing) return asProposal(fundId, existing.id)
  await page.go(`/accounts/${fundId}/voorstellen/new?kind=${kind}`)
  for (const [name, value] of Object.entries(fields)) {
    if (name === "acknowledge_risk") { await page.until(`!document.querySelector("[data-threshold-target=ackRow]").hidden`); await page.click("input[data-threshold-target=ack]"); continue }
    await page.fill(`[name=${name}]`, value)
  }
  await page.fill("input[name=title]", title)
  await page.submit("form[action$='/voorstellen']", "voorstellen/\\d+")
  const path = (await page.path()).split("?")[0]
  return { path, id: Number(path.match(/voorstellen\/(\d+)/)[1]), api: path.replace("voorstellen", "proposals"), fundId }
}

export const proposalJson = async (page, proposal) => {
  const response = await page.api("GET", proposal.api)
  must(response.status === 200, `GET proposal: ${response.status}`)
  return response.json
}

export async function review(page, proposal) {
  await page.go(proposal.path)
  await page.until(`document.querySelector("button[data-action='proposal-sign#review']")`, 30000)
  await walletReady(page)
  await page.click("button[data-action='proposal-sign#review']")
  await page.until(`document.querySelector("[data-controller~='proposal-sign'][data-flow-state='reviewed']")||document.querySelector("[data-proposal-sign-target=message][data-tone]")`, 30000)
}

export async function sign(page, proposal) {
  const current = await proposalJson(page, proposal)
  const own = await addressOf(USERS[page.name.replace("-switch", "")].wallet)
  if (current.signatures.some((row) => row.signer === own) || current.state !== "open") return
  await review(page, proposal)
  const tone = await toneOf(page, "proposal-sign")
  must(!tone, `review refused: ${await messageOf(page, "proposal-sign")}`)
  await page.click("button[data-action='proposal-sign#sign']")
  await page.until(`document.body.innerText.includes("Je hebt dit voorstel goedgekeurd")||document.querySelector("[data-proposal-sign-target=message][data-tone]")`, 30000)
  must(!await toneOf(page, "proposal-sign"), `sign refused: ${await messageOf(page, "proposal-sign")}`)
}

export async function openExecutePanel(page, proposal) {
  await page.go(proposal.path)
  await page.until(`document.querySelector("button[data-action='proposal-execute#check']")`, 30000)
  await walletReady(page)
}

// Click check, then execute. Returns the proposal as the server has it afterwards, and the transaction hash.
export async function execute(page, proposal) {
  await budget()
  const current = await proposalJson(page, proposal)
  if (current.state === "executed") return { hash: current.execution_tx_hash, json: current }
  await openExecutePanel(page, proposal)
  await page.click("button[data-action='proposal-execute#check']")
  await page.until(`document.querySelector("[data-execution-ready]")||document.querySelector("[data-proposal-execute-target=message][data-tone]")`, 30000)
  must(!await toneOf(page, "proposal-execute"), `check refused: ${await messageOf(page, "proposal-execute")}`)
  must(await page.eval(`document.querySelector("[data-controller~='proposal-execute']").dataset.executionReady`) === "true", "browser says not ready")
  await page.click("button[data-action='proposal-execute#execute']")
  await page.until(`(window.__sent||[]).length>0||document.querySelector("[data-proposal-execute-target=message][data-tone]")`, 60000)
  must(!await toneOf(page, "proposal-execute"), `execute refused: ${await messageOf(page, "proposal-execute")}`)
  const hash = (await page.eval("window.__sent")).at(-1)
  await page.until(`document.body.innerText.includes("Uitgevoerd op de blockchain")||document.querySelector("[data-proposal-execute-target=message][data-tone]")`, 300000)
  const json = await proposalJson(page, proposal)
  return { hash, json }
}

// Waits for chain state only: no sync request is made here, so the recurring job has to do it.
// Public RPC endpoints sit behind load balancers: right after a receipt, `latest` can still read the block before.
export async function eventually(label, check, ms = 60000) {
  const end = Date.now() + ms
  let seen
  while (Date.now() < end) {
    seen = await check()
    if (seen === true) return
    await sleep(3000)
  }
  throw new Error(`${label}: ${seen}`)
}

export async function pollUntil(label, work, ms = 300000, every = 5000) {
  const end = Date.now() + ms
  let last
  while (Date.now() < end) {
    last = await work()
    if (last) return last
    await sleep(every)
  }
  throw new Error(`timeout after ${ms} ms: ${label}`)
}
