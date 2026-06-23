#!/usr/bin/env bash
# Deterministic verification of the cmux-mobile PWA patch. exit 0 only if all pass.
# Boots the bridge on an isolated HOME so it never touches a real install.
set -u
BR="$(cd "$(dirname "$0")" && pwd)"; cd "$BR" || exit 1
fail=0
step(){ echo "[verify] $1"; }

step "node --check server.js"
node --check server.js || { echo "  FAIL syntax"; fail=1; }

step "upstream unit tests"
if node --test test/unit/*.test.mjs >/tmp/pwa_unit.log 2>&1; then echo "  ok"; else echo "  FAIL unit"; tail -5 /tmp/pwa_unit.log; fail=1; fi

step "sw.js bypasses every dynamic path (no caching of SSE/POST/status/cmux)"
grep -q 'u.pathname === "/" || u.pathname === "/manifest.webmanifest" || u.pathname.startsWith("/icons/")' sw.js \
  || { echo "  FAIL sw.js shell allowlist missing"; fail=1; }
grep -q 'if (!shell) return' sw.js || { echo "  FAIL sw.js does not bypass non-shell"; fail=1; }
grep -q 'method !== "GET"' sw.js || { echo "  FAIL sw.js does not bypass non-GET"; fail=1; }

step "boot isolated bridge + curl PWA routes"
TMPH="$(mktemp -d)"
HOME="$TMPH" PORT=7872 HOST=127.0.0.1 node server.js >/tmp/pwa_boot.log 2>&1 &
PID=$!; sleep 2
B="http://127.0.0.1:7872"
check(){ code=$(curl -s -m4 -o /dev/null -w "%{http_code}" "$B$1"); if [ "$code" = "$2" ]; then echo "  ok $1=$code"; else echo "  FAIL $1=$code want $2"; fail=1; fi; }
check /health 200
check / 200
check /manifest.webmanifest 200
check /sw.js 200
check /icons/icon-192.png 200
check /icons/icon-512.png 200
check /icons/icon-maskable-512.png 200
check /icons/nope.png 404
curl -s -m4 -D /tmp/pwa_hdr.txt "$B/manifest.webmanifest" -o /tmp/pwa_m.json
grep -qi "manifest+json" /tmp/pwa_hdr.txt && echo "  ok manifest content-type" || { echo "  FAIL manifest content-type"; fail=1; }
python3 -c "import json;json.load(open('/tmp/pwa_m.json'))" >/dev/null 2>&1 && echo "  ok manifest valid JSON" || { echo "  FAIL manifest JSON"; fail=1; }
curl -s -m4 "$B/" -o /tmp/pwa_idx.html
grep -q 'rel="manifest"' /tmp/pwa_idx.html && echo "  ok head: manifest link" || { echo "  FAIL no manifest link in /"; fail=1; }
grep -q "serviceWorker.register" /tmp/pwa_idx.html && echo "  ok head: SW register" || { echo "  FAIL no SW register in /"; fail=1; }
kill "$PID" 2>/dev/null; rm -rf "$TMPH"

if [ "$fail" -eq 0 ]; then echo "[verify] ALL PASS"; exit 0; else echo "[verify] FAILED"; exit 1; fi
