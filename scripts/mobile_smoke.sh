#!/bin/bash
# Browser smoke test of the mobile app's web build (react-native-web), using
# `jac browse` (bundled with jac) at a phone-sized viewport.
# Prereq:  source env.sh && jac run --dev --platform web mobile
#          (app on :8000, its API on :8001; override with APP=... API=...)
# Then:    bash scripts/mobile_smoke.sh
# It signs up a fresh user (via the API), loads demo data, then in the app:
# logs in, plans, accepts + rejects a suggestion, checks off a task, quick-adds.
APP=${APP:-http://localhost:8000}; B=${API:-http://localhost:8001}; J='Content-Type: application/json'; U=phone$RANDOM; PW=pw-phone-123
OUT="${TMPDIR:-/tmp}"
b() { jac browse -v 390x844 "$@" 2>&1 | tail -1; }
js() { b eval "$1"; }
tid() { echo "[data-testid=\"$1\"]"; }
click() { js "(()=>{const e=document.querySelector('$1'); if(!e) return 'NOT FOUND $1'; e.click(); return 'ok'})()" >/dev/null; sleep ${2:-2}; }
count() { js "document.querySelectorAll('$1').length"; }

curl -s -X POST $B/user/register -H "$J" -d "{\"identities\":[{\"type\":\"username\",\"value\":\"$U\"}],\"credential\":{\"type\":\"password\",\"password\":\"$PW\"}}" >/dev/null
T=$(curl -s -X POST $B/user/login -H "$J" -d "{\"identity\":{\"type\":\"username\",\"value\":\"$U\"},\"credential\":{\"type\":\"password\",\"password\":\"$PW\"}}" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])")
curl -s -X POST $B/api/mobile_api/walker/LoadDemo -H "$J" -H "Authorization: Bearer $T" -d '{}' >/dev/null

echo "== 1. open + log in"
b open $APP/ >/dev/null; sleep 4
js "localStorage.clear(); 'cleared'" >/dev/null; b navigate $APP/ >/dev/null; sleep 4
b fill "$(tid username)" $U >/dev/null; b fill "$(tid password)" $PW >/dev/null
js "[...document.querySelectorAll('[role=button],div')].find(e=>e.textContent.trim()=='Log in').click(); 'ok'" >/dev/null; sleep 4
echo "   screen: $(js "document.body.innerText.split('\n').slice(0,3).join(' | ')")"

echo "== 2. plan, then look at the next weekday"
js "[...document.querySelectorAll('div')].find(e=>e.textContent.trim()=='Plan').click(); 'ok'" >/dev/null; sleep 4
echo "   $(js "document.body.innerText.split('\n').find(l=>l.includes('suggestion')) || 'no notice'")"
for i in 1 2 3; do
  click "$(tid next-day)" 3
  [ "$(count '[data-testid^=accept-]')" != "0" ] && break
done
echo "   day: $(js "document.body.innerText.split('\n')[0]")  suggested=$(count '[data-testid^=accept-]')"
b screenshot "$OUT/mobile_day.png" >/dev/null

echo "== 3. accept one, reject one"
before=$(count '[data-testid^=accept-]')
click '[data-testid^=accept-]' 3
click '[data-testid^=reject-]' 3
echo "   suggested: $before -> $(count '[data-testid^=accept-]'), planned (finishable): $(count '[data-testid^=finish-]')"

echo "== 4. check off a task from its planned block"
click '[data-testid^=finish-]' 3
echo "   $(js "document.body.innerText.split('\n').find(l=>l.startsWith('Done:')) || document.body.innerText.split('\n').find(l=>l.toLowerCase().includes('error')) || 'no notice'")"

echo "== 5. quick add"
click "$(tid prev-day)" 1
b fill "$(tid quick-title)" "Buy lab goggles" >/dev/null
js "[...document.querySelectorAll('div')].find(e=>e.textContent.trim()=='Tomorrow').click(); 'ok'" >/dev/null; sleep 1
js "[...document.querySelectorAll('div')].find(e=>e.textContent.trim()=='30 min').click(); 'ok'" >/dev/null; sleep 1
js "[...document.querySelectorAll('div')].find(e=>e.textContent.trim()=='Add task').click(); 'ok'" >/dev/null; sleep 3
echo "   $(js "document.body.innerText.split('\n').find(l=>l.startsWith('Added:')) || 'no notice'")"
TM=$(python3 -c "from datetime import date,timedelta; print(date.today()+timedelta(days=1))")
echo "   server sees (due tomorrow): $(curl -s -X POST $B/api/mobile_api/walker/DayScreen -H "$J" -H "Authorization: Bearer $T" -d "{\"day\":\"$TM\"}" | python3 -c "import sys,json; print([(t['title'], t['estimated_minutes']) for t in json.load(sys.stdin)['data']['reports'][0]['due'] if 'goggles' in t['title']])")"
b screenshot "$OUT/mobile_today.png" >/dev/null

echo "== 6. log out"
click "$(tid logout)" 2
echo "   screen: $(js "document.body.innerText.split('\n').slice(0,2).join(' | ')")"
echo "== console errors:"; jac browse console 2>&1 | grep "\[error\]" | grep -v favicon | tail -5
echo "screenshots: $OUT/mobile_day.png $OUT/mobile_today.png"
