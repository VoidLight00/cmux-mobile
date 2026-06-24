#!/usr/bin/env bash
# Deterministic gate for the cmux control endpoints (tree/new/input/screen/key).
# Requires the bridge running on 127.0.0.1:7860 with cmux reachable. Creates a
# throwaway workspace, exercises every endpoint, then closes it. exit 0 only if
# all pass. The pairing code is read at runtime (never hardcoded — no secret here).
set -u
B="http://127.0.0.1:7860"
CODE="${CMUX_PAIR_CODE:-$(node "$(dirname "$0")/bin/cmux-iphone.js" pair 2>/dev/null | grep -oE '[0-9]{6}' | head -1)}"
[ -z "$CODE" ] && { echo "FAIL: no pairing code (set CMUX_PAIR_CODE)"; exit 1; }
TOK=$(curl -s -m8 "$B/pair" -H "content-type: application/json" -d "{\"code\":\"$CODE\"}" | python3 -c "import json,sys;print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
[ -z "$TOK" ] && { echo "FAIL: pair"; exit 1; }
AUTH=(-H "Authorization: Bearer $TOK")
NAME="verify-cmux-$$"; MARK="VERIFY_$$"; fail=0

echo "[1] /cmux/tree available + named workspaces"
curl -s -m8 "$B/cmux/tree" "${AUTH[@]}" | python3 -c "import json,sys;d=json.load(sys.stdin);assert d.get('available') and isinstance(d.get('workspaces'),list) and all('title' in w for w in d['workspaces'])" 2>/dev/null && echo "  ok" || { echo "  FAIL tree"; fail=1; }

echo "[2] POST /cmux/new"
curl -s -m12 "$B/cmux/new" "${AUTH[@]}" -H "content-type: application/json" -d "{\"command\":\"terminal\",\"name\":\"$NAME\"}" | grep -q '"ok":true' && echo "  ok" || { echo "  FAIL new"; fail=1; }
sleep 3
TID=$(curl -s -m8 "$B/cmux/tree" "${AUTH[@]}" | python3 -c "import json,sys;ws=[w for w in json.load(sys.stdin)['workspaces'] if w['title']=='$NAME'];print(ws[0]['terminals'][0]['id'] if ws and ws[0].get('terminals') else '')" 2>/dev/null)
WID=$(curl -s -m8 "$B/cmux/tree" "${AUTH[@]}" | python3 -c "import json,sys;ws=[w for w in json.load(sys.stdin)['workspaces'] if w['title']=='$NAME'];print(ws[0]['id'] if ws else '')" 2>/dev/null)
[ -n "$TID" ] && echo "  new workspace in tree ✓" || { echo "  FAIL new-not-in-tree"; fail=1; }

if [ -n "$TID" ]; then
  echo "[3] POST /cmux/input + screen reflects it"
  curl -s -m8 "$B/cmux/input" "${AUTH[@]}" -H "content-type: application/json" -d "{\"terminalId\":\"$TID\",\"text\":\"echo $MARK\"}" | grep -q '"ok":true' && echo "  input ok" || { echo "  FAIL input"; fail=1; }
  sleep 2
  curl -s -m8 "$B/cmux/screen?id=$TID" "${AUTH[@]}" | grep -q "$MARK" && echo "  screen echo ok" || { echo "  FAIL screen-echo"; fail=1; }
  echo "[4] POST /cmux/key (ctrl-c)"
  curl -s -m8 "$B/cmux/key" "${AUTH[@]}" -H "content-type: application/json" -d "{\"terminalId\":\"$TID\",\"key\":\"ctrl-c\"}" | grep -q '"ok":true' && echo "  key ok" || { echo "  FAIL key"; fail=1; }
fi

echo "[5] negative paths (보안 게이트 실측)"
c=$(curl -s -m6 -o /dev/null -w "%{http_code}" "$B/cmux/input" -H "content-type: application/json" -d '{"terminalId":"x","text":"y"}')
[ "$c" = "401" ] && echo "  unauth /cmux/input → 401 ok" || { echo "  FAIL unauth=$c"; fail=1; }
c=$(curl -s -m6 -o /dev/null -w "%{http_code}" "$B/cmux/new" "${AUTH[@]}" -H "content-type: application/json" -d '{"command":"sh -c evil"}')
[ "$c" = "400" ] && echo "  disallowed command → 400 ok" || { echo "  FAIL badcmd=$c"; fail=1; }
c=$(curl -s -m6 -o /dev/null -w "%{http_code}" "$B/cmux/key" "${AUTH[@]}" -H "content-type: application/json" -d '{"terminalId":"x","key":"rm-rf"}')
[ "$c" = "400" ] && echo "  unsupported key → 400 ok" || { echo "  FAIL badkey=$c"; fail=1; }

# cleanup (best-effort)
[ -n "$WID" ] && cmux close-workspace --workspace "$WID" >/dev/null 2>&1

if [ "$fail" -eq 0 ]; then echo "[verify-cmux] ALL PASS"; exit 0; else echo "[verify-cmux] FAILED"; exit 1; fi
