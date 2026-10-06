#!/bin/bash
# Browser smoke test of the mobile app's web build (react-native-web), using
# `jac browse` (bundled with jac) at a phone-sized viewport.
# Prereq:  source env.sh && jac run --dev --platform web mobile
#          (app on :8000, its API on :8001; override with APP=... API=...)
# Then:    bash scripts/mobile_smoke.sh
# It signs up a fresh user (via the API), loads demo data, then in the app:
# logs in, suggests a plan, accepts + rejects a suggestion, ticks a deadline,
# adds a task in the task sheet, opens Tasks / Ask Morrow / Settings, logs out.
APP=${APP:-http://localhost:8000}; B=${API:-http://localhost:8001}; J='Content-Type: application/json'; U=phone$RANDOM; PW=pw-phone-123
OUT="${TMPDIR:-/tmp}"
b() { jac browse -v 390x844 "$@" 2>&1 | tail -1; }
js() { b eval "$1"; }
tid() { echo "[data-testid=\"$1\"]"; }
click() { js "(()=>{const e=document.querySelector('$1'); if(!e) return 'NOT FOUND $1'; e.click(); return 'ok'})()" >/dev/null; sleep ${2:-2}; }
count() { js "document.querySelectorAll('$1').length"; }
# React-controlled inputs need the native setter + an input event.
setv() { js "(()=>{const el=document.querySelector('$1'); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el,'$2'); el.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'})()" >/dev/null; }
notice() { js "[...document.querySelectorAll('div')].map(d=>d.textContent).filter(t=>t.length<160).find(t=>/^(Added|Saved|Done|Planned|Cleared|All suggestions|[0-9]+ suggestion)/.test(t)) || 'no notice'"; }
walker() { local body='{}'; [ -n "$2" ] && body=$2; curl -s -X POST $B/api/mobile_api/walker/$1 -H "$J" -H "Authorization: Bearer $T" -d "$body"; }

curl -s -X POST $B/user/register -H "$J" -d "{\"identities\":[{\"type\":\"username\",\"value\":\"$U\"}],\"credential\":{\"type\":\"password\",\"password\":\"$PW\"}}" >/dev/null
T=$(curl -s -X POST $B/user/login -H "$J" -d "{\"identity\":{\"type\":\"username\",\"value\":\"$U\"},\"credential\":{\"type\":\"password\",\"password\":\"$PW\"}}" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])")
walker LoadDemo >/dev/null

echo "== 1. open + log in"
b open $APP/ >/dev/null; sleep 4
js "localStorage.clear(); 'cleared'" >/dev/null; b navigate $APP/ >/dev/null; sleep 4
b fill "$(tid username)" $U >/dev/null; b fill "$(tid password)" $PW >/dev/null
click "$(tid login-submit)" 5
echo "   screen: $(js "document.body.innerText.split('\n').slice(0,2).join(' | ')")"

echo "== 2. suggest, then find a day with suggestions"
click "$(tid suggest)" 5
echo "   $(notice)"
for d in $(python3 -c "from datetime import date,timedelta; print(' '.join(str(date.today()+timedelta(days=i)) for i in range(7)))"); do
  click "$(tid day-$d)" 2
  [ "$(count '[data-testid^=accept-]')" != "0" ] && break
done
echo "   day $d: suggested=$(count '[data-testid^=accept-]')"
b screenshot "$OUT/mobile_plan.png" >/dev/null

echo "== 3. accept one, reject one"
before=$(count '[data-testid^=accept-]')
click '[data-testid^=accept-]' 4
click '[data-testid^=reject-]' 4
echo "   suggested: $before -> $(count '[data-testid^=accept-]')"

echo "== 4. add a task in the task sheet"
click "$(tid add-task)" 2
setv "$(tid task-title)" "Buy lab goggles"; setv "$(tid task-time)" "17:00"
click "$(tid task-save)" 4
echo "   $(notice); sheets open: $(count "$(tid sheet-close)")"
echo "   server sees: $(walker TaskList '{"show_all":false}' | python3 -c "import sys,json; print([t['title'] for t in json.load(sys.stdin)['data']['reports'][0] if 'goggles' in t['title']])")"

echo "== 5. other tabs"
click "$(tid tab-tasks)" 3; echo "   Tasks: $(count '[data-testid^=task-check-]') rows"
click "$(tid tab-ask)" 3; echo "   Ask Morrow: input=$(count "$(tid chat-input)")"
click "$(tid tab-settings)" 3; echo "   Settings: name field=$(count "$(tid pref-name)") canvas=$(count "$(tid feed-url)")"
b screenshot "$OUT/mobile_settings.png" >/dev/null

echo "== 6. log out"
click "$(tid logout)" 3
echo "   screen: $(js "document.body.innerText.split('\n').slice(0,3).join(' | ')")"
echo "== console errors:"; jac browse console 2>&1 | grep "\[error\]" | grep -v favicon | tail -5
echo "screenshots: $OUT/mobile_plan.png $OUT/mobile_settings.png"
