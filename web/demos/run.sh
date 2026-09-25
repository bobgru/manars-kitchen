#!/bin/zsh
# Launch a browser demo end to end: seed its fixture, start the API server and
# the Vite dev server, run the demo, tear everything down.
#
#   web/demos/run.sh <demo> [demo flags...]
#
#   <demo>          current-period | feature-tour   (a file in web/demos/)
#   demo flags      --auto [ms]  --record  --headless  --slow <ms>   (see lib.mjs)
#
# Needs a built project (`stack build`) and `npm install` plus
# `npx playwright install chromium` done once in web/. Ports 8080 and 5173 are
# taken over; anything already listening on them is stopped first.
set -u

DEMO="${1:-}"
if [[ -z "$DEMO" ]]; then
  echo "usage: web/demos/run.sh <current-period|feature-tour> [--auto [ms]] [--record] [--headless]" >&2
  exit 2
fi
shift

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

case "$DEMO" in
  current-period) FIXTURE="demo/current-period.txt" ;;
  feature-tour)   FIXTURE="demo/restaurant-setup.txt" ;;
  *)
    if [[ -f "web/demos/$DEMO.mjs" ]]; then
      echo "no fixture mapping for '$DEMO'; add one to web/demos/run.sh" >&2
    else
      echo "unknown demo '$DEMO'; expected a file web/demos/$DEMO.mjs" >&2
    fi
    exit 2 ;;
esac

DB="/tmp/mk-demo-$DEMO.db"
SERVER_LOG="/tmp/mk-demo-server.log"
VITE_LOG="/tmp/mk-demo-vite.log"

stop_all() {
  lsof -ti:5173 -sTCP:LISTEN 2>/dev/null | xargs -r kill 2>/dev/null
  pkill -f "manars-server -- $DB" 2>/dev/null
}
trap stop_all EXIT INT TERM
stop_all
# Anything else already on the API port would answer for us with the wrong data.
lsof -ti:8080 -sTCP:LISTEN 2>/dev/null | xargs -r kill 2>/dev/null
sleep 1

echo "Seeding from $FIXTURE ..."
if ! stack exec manars-cli -- --demo "$FIXTURE" --no-delay > /tmp/mk-demo-seed.log 2>&1; then
  echo "seeding failed; see /tmp/mk-demo-seed.log" >&2
  exit 1
fi
# The replay leaves its rows in the WAL; checkpoint before copying or the copy
# has an empty calendar.
sqlite3 demo-db/demo.db "PRAGMA wal_checkpoint(TRUNCATE);" > /dev/null
rm -f "$DB" "$DB-wal" "$DB-shm"
cp demo-db/demo.db "$DB"

echo "Starting the API server on 8080 ..."
(stack exec manars-server -- "$DB" > "$SERVER_LOG" 2>&1 &)
if ! timeout 60 bash -c 'until curl -s -o /dev/null http://localhost:8080/api/config; do sleep 1; done'; then
  echo "the API server did not come up; see $SERVER_LOG" >&2
  exit 1
fi

echo "Starting the web dev server on 5173 ..."
cd web
(npm run dev > "$VITE_LOG" 2>&1 &)
if ! timeout 60 bash -c 'until curl -sf http://localhost:5173/ >/dev/null; do sleep 1; done'; then
  echo "the web dev server did not come up; see $VITE_LOG" >&2
  exit 1
fi

node "demos/$DEMO.mjs" "$@"
STATUS=$?
echo "Demo finished (exit $STATUS). Servers stopped."
exit $STATUS
