#!/bin/sh
# Rebuilds vendor/javascript/viem.js and the test-only accounts bundle from the committed lockfile.
# Dev machine or CI only; production needs no Node. Usage: vendor/viem-build/build.sh [workdir]
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${1:-$(mktemp -d)}

mkdir -p "$work"
cp "$here/package.build.json" "$work/package.json"
cp "$here/package-lock.build.json" "$work/package-lock.json"
cp "$here/entry.js" "$here/entry_test.js" "$work/"
cd "$work"

# Lifecycle scripts stay off; npm ci checks every tarball against the lockfile's integrity.
[ -d node_modules/viem ] || npm ci --ignore-scripts --no-audit --no-fund

common="--bundle --format=esm --target=es2022 --minify --tree-shaking=true --charset=utf8 --legal-comments=none --log-level=warning"
notice="Vendored by vendor/viem-build/build.sh. viem 2.57.11 (MIT) with @noble/curves, @noble/hashes, ox, abitype (MIT). See docs/VENDORED_JS.md"

node_modules/.bin/esbuild entry.js $common "--banner:js=/* $notice */" --outfile="$root/vendor/javascript/viem.js"
node_modules/.bin/esbuild entry_test.js $common "--banner:js=/* TEST ONLY. Never serve. $notice */" \
  --outfile="$root/test/javascript/support/vendor/viem_accounts.js"

shasum -a 256 "$root/vendor/javascript/viem.js" "$root/test/javascript/support/vendor/viem_accounts.js"
