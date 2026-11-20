#!/bin/bash
# Live end-to-end only (docs/ARCHITECTURE.md, Testing layers, layer 4). Never runs in CI.
# Boots the real app against its own database, with real Solid Queue (bin/jobs) and a toggleable
# outbound proxy, so an RPC outage on the server side is a real one, not a stub.
#   FT_E2E_OUT=<dir outside the repo> test/e2e/serve.sh reset    # drop and recreate the database first
#   FT_E2E_OUT=<dir outside the repo> test/e2e/serve.sh          # start
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
: "${FT_E2E_OUT:?set FT_E2E_OUT to a directory outside the repo}"
PORT="${FT_E2E_PORT:-3458}"
PROXY_PORT="${FT_E2E_PROXY_PORT:-3459}"
DB="${FT_E2E_DB:-ft_e2e_live}"

export DATABASE_URL="postgres:///$DB" RAILS_ENV=development RAILS_MAX_THREADS=8 PORT
export FUNDTOGETHER_ORIGIN="http://localhost:$PORT" FUNDTOGETHER_CHAINS=sepolia
export SOLID_QUEUE_IN_DEV=1 LAUNCHY_DRY_RUN=true SKIP_TEST_DATABASE=true
export http_proxy="http://127.0.0.1:$PROXY_PORT"

cd "$ROOT" || exit 1
mkdir -p "$FT_E2E_OUT"

if [ "${1:-}" = "reset" ]; then
  psql -q -d postgres -c "DROP DATABASE IF EXISTS $DB"
  env -u http_proxy bundle exec rails db:create db:schema:load
  env -u http_proxy bundle exec rails runner 'load Rails.root.join("db/queue_schema.rb")' >/dev/null
  rm -rf tmp/letter_opener
fi

node "$HERE/proxy.mjs" "$PROXY_PORT" "$FT_E2E_OUT/rpc_down" &
PROXY=$!
bundle exec bin/jobs >"$FT_E2E_OUT/jobs.log" 2>&1 &
JOBS=$!
trap 'kill $PROXY $JOBS 2>/dev/null; wait $PROXY $JOBS 2>/dev/null' EXIT INT TERM
bundle exec puma -b "tcp://127.0.0.1:$PORT" -t 8:8 config.ru >"$FT_E2E_OUT/puma.log" 2>&1
