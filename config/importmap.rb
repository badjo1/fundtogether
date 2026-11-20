# Pin npm packages by running ./bin/importmap

# Subresource integrity for every module, also dynamic imports. See docs/ARCHITECTURE.md, Threat model: this catches a
# file altered behind the app (a CDN, a cache), not a server that serves altered pages and hashes together.
enable_integrity!

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Wallet layer: no dependencies, small, used by the wallet controller on any page.
pin_all_from "app/javascript/wallet", under: "wallet"
# Safe layer and viem load through dynamic import when a flow starts. Signing pages only.
pin_all_from "app/javascript/safe", under: "safe", preload: false
# Single committed build; version and SHA-256 in docs/VENDORED_JS.md.
pin "viem", to: "viem.js", preload: false
