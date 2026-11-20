// Guards on what reaches the browser. These read files: no module loading.
import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { readFileSync, readdirSync, statSync } from "node:fs"
import { join, relative } from "node:path"
import { describe, test } from "node:test"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("../..", import.meta.url))

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    return statSync(path).isDirectory() ? walk(path) : [path]
  })
}

const appFiles = walk(join(root, "app/javascript")).filter((path) => path.endsWith(".js"))
const LEGACY_CONTROLLERS = /controllers\/(application|clipboard|confirm_modal|dapp|dropdown|flash|hello|index|modal)(_controller)?\.js$/
const ownFiles = appFiles.filter((path) => !LEGACY_CONTROLLERS.test(path))
const importmap = readFileSync(join(root, "config/importmap.rb"), "utf8")
const viem = readFileSync(join(root, "vendor/javascript/viem.js"))
const viemText = viem.toString("utf8")

describe("the test provider stays out of the app", () => {
  for (const file of appFiles) {
    test(`${relative(root, file)} has no test-only code`, () => {
      const source = readFileSync(file, "utf8")
      assert.doesNotMatch(source, /test_provider|TestProvider|viem_accounts|privateKey|test\/javascript/)
    })
  }

  test("the importmap pins nothing from test/", () => {
    assert.doesNotMatch(importmap, /test_provider|viem_accounts|test\/javascript/)
  })

  test("the test provider is not under a served asset path", () => {
    const assetPaths = ["app/assets", "app/javascript", "vendor/assets", "vendor/javascript", "public"]
    for (const base of assetPaths) {
      let files = []
      try {
        files = walk(join(root, base))
      } catch {
        continue
      }
      assert.deepEqual(files.filter((path) => /test_provider|viem_accounts/.test(path)), [])
    }
  })

  test("viem's local-signing code is not in the app bundle", () => {
    assert.doesNotMatch(viemText, /privateKeyToAccount|signTransaction|mnemonic/i)
  })
})

describe("the vendored build", () => {
  test("has no eval, new Function or WebAssembly, for a strict CSP", () => {
    assert.doesNotMatch(viemText, /\beval\s*\(/)
    assert.doesNotMatch(viemText, /new\s+Function\b/)
    assert.doesNotMatch(viemText, /\bFunction\s*\(/)
    assert.doesNotMatch(viemText, /WebAssembly/)
  })

  test("is one file with no imports and no network or storage use", () => {
    assert.doesNotMatch(viemText, /(^|[;}\s])import\s*[\s{"'(*]/)
    assert.doesNotMatch(viemText, /\bimport\s*\(/)
    assert.doesNotMatch(viemText, /\b(fetch|XMLHttpRequest|WebSocket|localStorage|sessionStorage)\b/)
  })

  test("matches the SHA-256 recorded in docs/VENDORED_JS.md", () => {
    const docs = readFileSync(join(root, "docs/VENDORED_JS.md"), "utf8")
    const hash = createHash("sha256").update(viem).digest("hex")
    assert.ok(docs.includes(hash), `docs do not record ${hash}`)
  })

  test("no package.json in the repo", () => {
    assert.throws(() => statSync(join(root, "package.json")))
    assert.throws(() => statSync(join(root, "test/javascript/package.json")))
    assert.throws(() => statSync(join(root, "vendor/viem-build/package.json")))
  })
})

describe("the wallet and Safe JavaScript", () => {
  for (const file of ownFiles) {
    test(`${relative(root, file)} is CSP clean`, () => {
      const source = readFileSync(file, "utf8")
      assert.doesNotMatch(source, /\beval\s*\(|new\s+Function\b|\.innerHTML\s*=|setTimeout\s*\(\s*["'`]/)
    })
  }

  test("controllers never import viem or safe/ statically, so ordinary pages stay light", () => {
    for (const file of appFiles.filter((path) => path.includes("/controllers/"))) {
      const source = readFileSync(file, "utf8")
      assert.doesNotMatch(source, /^import .*from\s+"(viem|safe\/[^"]*)"/m, relative(root, file))
    }
  })

  test("wallet/ stays free of viem", () => {
    for (const file of appFiles.filter((path) => path.includes("/wallet/"))) {
      assert.doesNotMatch(readFileSync(file, "utf8"), /from\s+"(viem|safe\/[^"]*)"/, relative(root, file))
    }
  })

  test("no floats on amounts in safe/", () => {
    for (const file of appFiles.filter((path) => path.includes("/safe/"))) {
      assert.doesNotMatch(readFileSync(file, "utf8"), /parseFloat|toFixed|Number\(\s*(amount|value|units)/, relative(root, file))
    }
  })

  test("every step and error shown by a controller has Dutch text", () => {
    const errors = readFileSync(join(root, "app/javascript/wallet/errors.js"), "utf8")
    const codes = new Set()
    for (const file of appFiles) {
      for (const match of readFileSync(file, "utf8").matchAll(/(?:refuse|WalletError)\(\s*"([a-z_0-9]+)"/g)) codes.add(match[1])
      for (const match of readFileSync(file, "utf8").matchAll(/noWalletCode|"(no_wallet_[a-z]+|in_app_browser)"/g)) if (match[1]) codes.add(match[1])
    }
    for (const code of codes) assert.match(errors, new RegExp(`^\\s+${code}: `, "m"), code)
    assert.ok(codes.size > 40)
  })

  test("every step has Dutch text", () => {
    const errors = readFileSync(join(root, "app/javascript/wallet/errors.js"), "utf8")
    const steps = new Set()
    for (const file of ownFiles) {
      for (const match of readFileSync(file, "utf8").matchAll(/(?:onStep|publishStep)\((?:this, )?"([a-z_]+)"/g)) steps.add(match[1])
    }
    assert.ok(steps.size > 15)
    for (const step of steps) assert.match(errors, new RegExp(`^\\s+${step}: "`, "m"), step)
  })

  test("docs/FRONTEND_CONTRACT.md lists every error code", () => {
    const errors = readFileSync(join(root, "app/javascript/wallet/errors.js"), "utf8")
    const section = errors.slice(errors.indexOf("export const MESSAGES"), errors.indexOf("// Contract revert codes"))
    const contract = readFileSync(join(root, "docs/FRONTEND_CONTRACT.md"), "utf8")
    const codes = [...section.matchAll(/^ {2}([a-z_0-9]+): /gm)].map((match) => match[1])
    assert.ok(codes.length > 60)
    for (const code of codes) assert.ok(contract.includes(`\`${code}\``), code)
  })
})
