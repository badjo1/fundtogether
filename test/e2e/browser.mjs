// Headless Chrome over the DevTools protocol, one browser context per user. Real clicks on real pages.
// Each wallet context gets test/javascript/support/test_provider.js, injected before any page script.
import { spawn } from "node:child_process"
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { CHAIN_ID, CHAIN_HEX, EURC, FACTORY, ROOT, SINGLETON, RPC_URLS, identity } from "./chain.mjs"

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const DEBUG_PORT = Number(process.env.FT_E2E_DEBUG_PORT || 9348)
const RPC_PATTERNS = RPC_URLS.map((url) => `${url}*`)

// The provider's chain is fixed to Sepolia here: chain 1 has no RPC, so the wrong-network case cannot
// reach another chain. Every eth_sendTransaction is checked again before TestProvider signs it.
function providerBundle(names) {
  const vendor = readFileSync(`${ROOT}/test/javascript/support/vendor/viem_accounts.js`, "utf8").replace(/export\{Io as privateKeyToAccount\};?\s*$/, "const __pk=Io;")
  const provider = readFileSync(`${ROOT}/test/javascript/support/test_provider.js`, "utf8").replace(/^import .*$/m, "const privateKeyToAccount=__pk;").replace(/^export /gm, "")
  const keys = names.map((name) => identity()[name].key)
  return `(()=>{${vendor}\n${provider}\n
    const p=new TestProvider({privateKeys:${JSON.stringify(keys)},chains:{${CHAIN_ID}:${JSON.stringify(RPC_URLS[0])}},chainId:${CHAIN_ID},allowSend:true,fetch:(...a)=>window.fetch(...a)});
    try{ if(localStorage.getItem("__e2e_auth")) p.authorized=true }catch(e){}
    const orig=p.request.bind(p);
    const guard=async(tx)=>{
      if(p.chainId!==${CHAIN_ID}) throw Object.assign(new Error("E2E guard: not Sepolia"),{code:4901});
      if(await p.rpc("eth_chainId",[])!=="${CHAIN_HEX}") throw Object.assign(new Error("E2E guard: RPC is not Sepolia"),{code:4901});
      if(BigInt(tx.value??"0x0")!==0n) throw Object.assign(new Error("E2E guard: the app sends no value"),{code:4200});
      const to=String(tx.to).toLowerCase();
      if(to==="${FACTORY}"||to==="${EURC}") return;
      const slot=await p.rpc("eth_getStorageAt",[to,"0x0","latest"]);
      if(("0x"+slot.slice(-40))!=="${SINGLETON}") throw Object.assign(new Error("E2E guard: target is not a canonical Safe"),{code:4200});
    };
    window.__prompts=[];
    window.__hold=null;
    p.request=async(a)=>{
      const prompt=["personal_sign","eth_signTypedData_v4","eth_sendTransaction"].includes(a.method);
      if(prompt) window.__prompts.push(a.method);
      if(window.__hold===a.method){ window.__hold=null; window.__held=a.method; await new Promise(r=>{window.__release=r}); }
      if(a.method==="eth_sendTransaction") await guard(a.params[0]);
      const r=await orig(a);
      if(a.method==="eth_requestAccounts"){try{localStorage.setItem("__e2e_auth","1")}catch(e){}}
      if(a.method==="eth_sendTransaction"){window.__sent=(window.__sent||[]).concat(r)}
      return r;
    };
    window.__provider=p;
    installTestProvider(window,p);
  })();`
}

const CSP_WATCH = `window.__csp=[];document.addEventListener("securitypolicyviolation",e=>window.__csp.push(e.violatedDirective+" "+e.blockedURI+" "+location.pathname));`

export class Browser {
  constructor({ out, base, log }) { Object.assign(this, { out, base, log, problems: { csp: [], console: [], http5xx: [] } }) }

  async start() {
    this.profile = `${this.out}/chrome-profile`
    rmSync(this.profile, { recursive: true, force: true })
    mkdirSync(this.profile, { recursive: true })
    this.chrome = spawn(CHROME, ["--headless=new", "--no-first-run", "--disable-gpu", "--disable-extensions", "--disable-background-networking", `--remote-debugging-port=${DEBUG_PORT}`, `--user-data-dir=${this.profile}`, "about:blank"], { stdio: "ignore" })
    let version
    for (let i = 0; i < 100 && !version; i++) { await sleep(200); try { version = await (await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/version`)).json() } catch {} }
    if (!version) throw new Error("Chrome did not start")
    this.ws = new WebSocket(version.webSocketDebuggerUrl)
    await new Promise((resolve) => { this.ws.onopen = resolve })
    this.id = 0; this.waiting = new Map(); this.handlers = new Map()
    this.ws.onmessage = (message) => {
      const msg = JSON.parse(message.data)
      if (msg.id && this.waiting.has(msg.id)) {
        const { res, rej } = this.waiting.get(msg.id)
        this.waiting.delete(msg.id)
        return msg.error ? rej(new Error(`CDP: ${msg.error.message}`)) : res(msg.result)
      }
      if (msg.sessionId) this.handlers.get(msg.sessionId)?.(msg)
    }
  }

  send(method, params = {}, sessionId) {
    const id = ++this.id
    // A DevTools command that never answers (an open dialog, a crashed target) fails loudly instead of hanging the run.
    return new Promise((res, rej) => {
      const timer = setTimeout(() => { this.waiting.delete(id); rej(new Error(`DevTools ${method} gave no answer in 90 s`)) }, 90000)
      this.waiting.set(id, { res: (value) => { clearTimeout(timer); res(value) }, rej: (error) => { clearTimeout(timer); rej(error) } })
      this.ws.send(JSON.stringify({ id, method, params, sessionId }))
    })
  }

  async page(name, { wallets = [] } = {}) {
    const { browserContextId } = await this.send("Target.createBrowserContext")
    const { targetId } = await this.send("Target.createTarget", { url: "about:blank", browserContextId, width: 1280, height: 1000 })
    const { sessionId } = await this.send("Target.attachToTarget", { targetId, flatten: true })
    const page = new Page(this, name, sessionId, wallets)
    await page.init()
    return page
  }

  async stop() {
    this.chrome?.kill()
    await sleep(500)
    rmSync(this.profile, { recursive: true, force: true })
  }
}

export class Page {
  constructor(browser, name, session, wallets) { Object.assign(this, { browser, name, session, wallets, tamper: null, rpcBlocked: false }) }

  cmd(method, params) { return this.browser.send(method, params, this.session) }

  async init() {
    this.browser.handlers.set(this.session, (message) => this.on(message))
    for (const domain of ["Page", "Runtime", "Log", "Network"]) await this.cmd(`${domain}.enable`)
    await this.cmd("Page.addScriptToEvaluateOnNewDocument", { source: CSP_WATCH })
    if (this.wallets.length > 0) await this.cmd("Page.addScriptToEvaluateOnNewDocument", { source: providerBundle(this.wallets) })
    await this.cmd("Emulation.setDeviceMetricsOverride", { width: 1280, height: 1000, deviceScaleFactor: 1, mobile: false })
  }

  on(message) {
    const { problems } = this.browser
    if (message.method === "Fetch.requestPaused") return this.paused(message.params)
    if (message.method === "Log.entryAdded") {
      const { entry } = message.params
      if (/Content Security Policy/i.test(entry.text)) problems.csp.push(`${this.name}: ${entry.text}`)
      else if (entry.level === "error" && !/status of 4\d\d|favicon/.test(entry.text) && !this.rpcBlocked) problems.console.push(`${this.name}: ${entry.text} ${entry.url || ""}`.slice(0, 240))
    }
    if (message.method === "Runtime.exceptionThrown") problems.console.push(`${this.name} exception: ${message.params.exceptionDetails.exception?.className || message.params.exceptionDetails.text}`.slice(0, 200))
    if (message.method === "Network.responseReceived" && message.params.response.status >= 500) problems.http5xx.push(`${this.name}: ${message.params.response.status} ${message.params.response.url}`)
  }

  // --- Response-layer tampering and RPC blocking, both in this browser only.

  async setFetch() {
    const patterns = []
    if (this.rpcBlocked) patterns.push(...RPC_PATTERNS.map((urlPattern) => ({ urlPattern, requestStage: "Request" })))
    if (this.tamper) patterns.push({ urlPattern: "*/accounts/*", resourceType: "Fetch", requestStage: "Response" })
    if (patterns.length > 0) await this.cmd("Fetch.enable", { patterns })
    else await this.cmd("Fetch.disable")
  }

  async blockRpc(on) { this.rpcBlocked = on; await this.setFetch() }
  async setTamper(tamper) { this.tamper = tamper; await this.setFetch() }

  async paused({ requestId, request, responseStatusCode, responseHeaders }) {
    try {
      if (RPC_URLS.some((url) => request.url.startsWith(url))) {
        if (this.rpcBlocked) return await this.cmd("Fetch.failRequest", { requestId, errorReason: "ConnectionFailed" })
        return await this.cmd("Fetch.continueRequest", { requestId })
      }
      if (this.tamper && responseStatusCode !== undefined && this.tamper.match.test(new URL(request.url).pathname) && request.method === "GET") {
        const { body, base64Encoded } = await this.cmd("Fetch.getResponseBody", { requestId })
        const text = base64Encoded ? Buffer.from(body, "base64").toString("utf8") : body
        const changed = JSON.stringify(this.tamper.mutate(JSON.parse(text)))
        return await this.cmd("Fetch.fulfillRequest", { requestId, responseCode: responseStatusCode, responseHeaders, body: Buffer.from(changed).toString("base64") })
      }
      await this.cmd(responseStatusCode !== undefined ? "Fetch.continueResponse" : "Fetch.continueRequest", { requestId })
    } catch { /* The page moved on; nothing to resume. */ }
  }

  // --- Page helpers

  async eval(expression) {
    const result = await this.cmd("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true })
    if (result.exceptionDetails) throw new Error(`eval failed on ${expression.slice(0, 100)}: ${result.exceptionDetails.exception?.description?.split("\n")[0] || result.exceptionDetails.text}`)
    return result.result.value
  }

  async go(path) {
    await this.cmd("Page.navigate", { url: path.startsWith("http") ? path : this.browser.base + path })
    await sleep(350)
    await this.until("document.readyState==='complete'")
    await this.settle()
  }

  async until(expression, ms = 20000) {
    const end = Date.now() + ms
    while (Date.now() < end) {
      try { if (await this.eval(`!!(${expression})`)) return true } catch {}
      await sleep(150)
    }
    throw new Error(`timeout (${ms} ms) on ${this.name} at ${await this.eval("location.pathname").catch(() => "?")}: ${expression.slice(0, 140)}`)
  }

  async settle(ms = 30000) {
    await this.until(`!document.querySelector('turbo-frame [aria-busy=true]') && !document.querySelector('turbo-frame[busy]')`, ms).catch(() => {})
    await sleep(200)
  }

  path() { return this.eval("location.pathname+location.search") }
  text() { return this.eval("document.body.innerText") }

  fill(selector, value) {
    return this.eval(`(()=>{const e=document.querySelector(${JSON.stringify(selector)}); if(!e) throw new Error("no element"); e.value=${JSON.stringify(value)}; e.dispatchEvent(new Event("input",{bubbles:true})); e.dispatchEvent(new Event("change",{bubbles:true}))})()`)
  }

  // A real pointer click at the element's centre, so hidden or covered buttons fail like they do for a person.
  async click(selector) {
    const box = await this.eval(`(()=>{const e=[...document.querySelectorAll(${JSON.stringify(selector)})].find(x=>x.getClientRects().length>0&&!x.closest("[hidden]")); if(!e) return null; e.scrollIntoView({block:"center"}); const r=e.getBoundingClientRect(); const top=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2); return {x:r.x+r.width/2,y:r.y+r.height/2,hit:e===top||e.contains(top)||(top&&top.contains(e)),disabled:!!e.disabled}})()`)
    if (!box) throw new Error(`no visible element for ${selector} at ${await this.path()}`)
    if (box.disabled) throw new Error(`disabled: ${selector}`)
    if (!box.hit) throw new Error(`covered: ${selector}`)
    for (const type of ["mousePressed", "mouseReleased"]) await this.cmd("Input.dispatchMouseEvent", { type, x: box.x, y: box.y, button: "left", clickCount: 1 })
  }

  async clickText(selector, text) {
    const marked = await this.eval(`(()=>{const e=[...document.querySelectorAll(${JSON.stringify(selector)})].find(x=>x.textContent.includes(${JSON.stringify(text)})&&x.getClientRects().length>0); if(!e) return false; e.setAttribute("data-e2e-click","1"); return true})()`)
    if (!marked) throw new Error(`no ${selector} with text ${text} at ${await this.path()}`)
    await this.click("[data-e2e-click='1']")
    await this.eval(`document.querySelector("[data-e2e-click='1']")?.removeAttribute("data-e2e-click")`).catch(() => {})
  }

  async submit(selector, nextPathPattern) {
    const before = await this.path()
    await this.eval(`document.querySelector(${JSON.stringify(selector)}).requestSubmit()`)
    await this.until(nextPathPattern ? `new RegExp(${JSON.stringify(nextPathPattern)}).test(location.pathname+location.search)` : `location.pathname+location.search!==${JSON.stringify(before)}`)
    await sleep(300)
    await this.settle()
  }

  async shot(name) {
    const metrics = await this.cmd("Page.getLayoutMetrics")
    const height = Math.min(Math.ceil(metrics.cssContentSize.height), 3400)
    const { data } = await this.cmd("Page.captureScreenshot", { format: "png", captureBeyondViewport: true, clip: { x: 0, y: 0, width: 1280, height, scale: 1 } })
    mkdirSync(process.env.FT_E2E_SCREENS, { recursive: true })
    writeFileSync(`${process.env.FT_E2E_SCREENS}/${name}.png`, Buffer.from(data, "base64"))
    const violations = await this.eval("window.__csp||[]").catch(() => [])
    if (violations.length) this.browser.problems.csp.push(...violations.map((entry) => `${this.name}: ${entry}`))
    await this.eval("window.__csp=[]").catch(() => {})
  }

  // Same-origin JSON through the browser's own session and CSRF token.
  api(method, path, body) {
    return this.eval(`(async()=>{const r=await fetch(${JSON.stringify(path)},{method:${JSON.stringify(method)},credentials:"same-origin",headers:{"Accept":"application/json","Content-Type":"application/json","X-CSRF-Token":document.querySelector("meta[name=csrf-token]")?.content||""},body:${body ? JSON.stringify(JSON.stringify(body)) : "undefined"}});const t=await r.text();let j=null;try{j=JSON.parse(t)}catch{};return {status:r.status,json:j,text:j?null:t.slice(0,200)}})()`)
  }
}
