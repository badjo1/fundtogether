// Node module hooks that give tests the same bare specifiers as config/importmap.rb, with no
// package.json in the repo. Files under app/, vendor/ and test/javascript/ are ES modules.
import { pathToFileURL } from "node:url"
import { existsSync } from "node:fs"
import { dirname, resolve as resolvePath } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const root = resolvePath(here, "../../..")
const MODULE_ROOTS = [`${root}/app/javascript/`, `${root}/vendor/javascript/`, `${root}/test/javascript/`]

function file(path) {
  return pathToFileURL(resolvePath(root, path)).href
}

function bareTarget(specifier) {
  if (specifier === "viem") return file("vendor/javascript/viem.js")
  if (specifier === "@hotwired/stimulus") return file("test/javascript/support/stimulus_stub.js")
  const match = specifier.match(/^(wallet|safe|controllers)\/([a-z0-9_/]+)$/)
  if (match) {
    const path = `app/javascript/${match[1]}/${match[2]}.js`
    if (existsSync(resolvePath(root, path))) return file(path)
  }
  return null
}

export async function resolve(specifier, context, next) {
  const target = bareTarget(specifier)
  if (target) return { url: target, format: "module", shortCircuit: true }
  return next(specifier, context)
}

export async function load(url, context, next) {
  if (url.startsWith("file:") && url.endsWith(".js")) {
    const path = fileURLToPath(url)
    if (MODULE_ROOTS.some((prefix) => path.startsWith(prefix))) {
      return next(url, { ...context, format: "module" })
    }
  }
  return next(url, context)
}
