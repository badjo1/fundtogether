# Vendored JavaScript

The browser's only third-party JavaScript beyond Turbo and Stimulus. Production needs no Node: the output
is committed and served by Propshaft through the importmap.

| File | Package | SHA-256 | Size |
|---|---|---|---|
| `vendor/javascript/viem.js` | viem 2.57.11, tree-shaken to `vendor/viem-build/entry.js` | `10e91b8060efc63a42d70ebba9ab7b36d5af9b10ebef607c8e6c399a8f8cd781` | 92704 bytes, 31943 gzipped |
| `test/javascript/support/vendor/viem_accounts.js` | viem 2.57.11 `privateKeyToAccount`. Test only, never served | `0a4a143dda38f139abc14327786002c1149833b7940c5dfedbc14621ef286db1` | n/a |

`viem` integrity, checked against both the lockfile and the npm registry on 2026-11-09:
`sha512-kvcBGXzIGmZu3GqaA83ZOLzVC57YO7WCgQrGcUHNKqZ8Cjqc9vV//uGna4Nhv0NGHn2gekw1FNdSvQePNnYePQ==`

Built with esbuild 0.28.2: `--bundle --format=esm --target=es2022 --minify --tree-shaking=true`.
Bundled licences are MIT: viem, ox, abitype, @noble/curves, @noble/hashes.

## Rebuild

```sh
vendor/viem-build/build.sh            # npm ci --ignore-scripts from the lockfile in a temp dir, then esbuild
```

`vendor/viem-build/` holds the entries and the lockfile under names no Node tool picks up
(`package.build.json`, `package-lock.build.json`), so the repo has no `package.json`. Pick versions at
least 14 days old. After a rebuild, update the table above; `test/javascript/isolation.test.mjs` compares
the hash, and also fails on `eval`, `new Function`, `WebAssembly`, imports, network or storage use, and
local-key code in the build.

To widen what ships, add a named export to `entry.js`. Only the Safe signing pages load this file, through
dynamic import from `app/javascript/safe`. `wallet/` and the controllers' top-level imports stay free of it.

## JS tests

```sh
cd test/javascript && node --test
```

No `package.json` and no install. `support/hooks.mjs` maps the importmap's bare specifiers to files for Node.
Stimulus is stubbed under Node, so real wiring needs the browser run.

`node live/read_only_check.mjs [safe]` reads a real Sepolia Safe through the app's code path. It sends nothing.
