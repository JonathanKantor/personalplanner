#!/bin/bash
# Browser smoke test of the web app (uses `jac browse`, bundled with jac).
# Start the server first (source env.sh && jac run), then: bash scripts/web_smoke.sh
# It signs up a fresh user, loads demo data, adds a task, suggests/accepts/
# rejects/adjusts blocks, checks the OAuth callback errors, and logs out.
# Step 6 opens Google's sign-in page in the headless browser (nothing is submitted).
S="${TMPDIR:-/tmp}"
B="jac browse"
js() { $B eval "$1" 2>&1 | tail -1; }
click_text() { js "(()=>{const b=[...document.querySelectorAll('button,a')].find(x=>x.textContent.trim().startsWith('$1')); if(!b) return 'NOT FOUND: $1'; b.click(); return 'clicked $1'})()"; sleep ${2:-2}; }
U=web$RANDOM
setv() { js "(()=>{const el=document.querySelector('$1'); const set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set; set.call(el,'$2'); el.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'})()" >/dev/null; }

echo "== 1. signup through the UI"
$B navigate http://localhost:8000/ >/dev/null; sleep 2; click_text "Log out" 2 >/dev/null
$B navigate http://localhost:8000/ >/dev/null; $B wait '#username' >/dev/null
echo "   redirected to: $($B get url | tail -1)"
click_text "Create an account" 1
$B fill '#username' $U >/dev/null; $B fill '#password' pw-web-12345 >/dev/null; $B click '#submit' >/dev/null; $B wait '.week' >/dev/null
echo "   after signup: $($B get url | tail -1)"

echo "== 2. settings: load demo, preferences"
$B navigate http://localhost:8000/settings >/dev/null; $B wait '#save-prefs' >/dev/null
click_text "Load demo classes" 3
echo "   notice: $(js 'document.querySelector(".notice")?.textContent')"
echo "   calendars listed: $(js '[...document.querySelectorAll(".panel .list li b")].map(x=>x.textContent).join(", ")')"
js "(()=>{const s=document.querySelector('#work_start'); const set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set; set.call(s,'08:30'); s.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'})()" >/dev/null
for d in sat sun; do js "[...document.querySelectorAll('label.row')].find(l=>l.textContent.trim()=='$d').querySelector('input').click()" >/dev/null; done
$B click '#save-prefs' >/dev/null; sleep 2
echo "   after save: $(js 'document.querySelector(".notice")?.textContent || document.querySelector(".error")?.textContent')"
$B screenshot $S/settings.png >/dev/null

echo "== 3. tasks: add one through the form"
$B navigate http://localhost:8000/tasks >/dev/null; $B wait '#title' >/dev/null
DUE=$(python3 -c "from datetime import datetime,timedelta; print((datetime.now()+timedelta(days=3)).strftime('%Y-%m-%dT17:00'))")
$B fill '#title' "Essay draft" >/dev/null; setv '#due' "$DUE"; setv '#minutes' 90; $B fill '#course' "ENGLISH 125" >/dev/null
js "(()=>{const s=document.querySelector('#priority'); s.value='high'; s.dispatchEvent(new Event('change',{bubbles:true})); return 'ok'})()" >/dev/null
$B click '#save' >/dev/null; sleep 2
echo "   notice: $(js 'document.querySelector(".notice")?.textContent || document.querySelector(".error")?.textContent')"
echo "   tasks: $(js '[...document.querySelectorAll(".list li b")].map(x=>x.textContent).join(" | ")')"
echo "   essay row: $(js '[...document.querySelectorAll(".list li")].find(l=>l.textContent.includes("Essay"))?.querySelector(".reason")?.textContent')"
$B screenshot $S/tasks.png >/dev/null

echo "== 4. week: suggest, accept one, reject one, adjust one"
$B navigate http://localhost:8000/ >/dev/null; $B wait '.week' >/dev/null; sleep 1
click_text "Suggest schedule" 3
echo "   suggested in grid: $(js 'document.querySelectorAll(".item.suggested").length')"
js '[...document.querySelectorAll(".panel .list li")].slice(0,1).map(l=>l.querySelector(".btn.primary").click()).length' >/dev/null; sleep 2
echo "   after accept: planned=$(js 'document.querySelectorAll(".item.accepted").length') suggested=$(js 'document.querySelectorAll(".item.suggested").length')"
js '[...document.querySelectorAll(".panel .list li")][0].querySelector(".btn.danger").click()' >/dev/null; sleep 2
echo "   after reject: suggested=$(js 'document.querySelectorAll(".item.suggested").length')"
js '[...document.querySelectorAll(".panel .list li")][0].querySelectorAll(".btn")[1].click()' >/dev/null; sleep 1
echo "   adjust form open: $(js '!!document.querySelector(".panel .list input[type=time]")')"
js "(()=>{const i=document.querySelectorAll('.panel .list input[type=time]'); const set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set; set.call(i[0],'12:15'); i[0].dispatchEvent(new Event('input',{bubbles:true})); set.call(i[1],'12:45'); i[1].dispatchEvent(new Event('input',{bubbles:true})); return 'ok'})()" >/dev/null
click_text "Save" 2
echo "   adjust result: error=$(js 'document.querySelector(".error")?.textContent || "none"')  planned=$(js 'document.querySelectorAll(".item.accepted").length')"
$B screenshot $S/week3.png >/dev/null

echo "== 5. oauth callback page handles errors"
$B navigate "http://localhost:8000/oauth/callback?error=access_denied" >/dev/null; sleep 2
echo "   $(js 'document.querySelector(".error")?.textContent')"
$B navigate "http://localhost:8000/oauth/callback?code=fake&state=forged" >/dev/null; sleep 3
echo "   $(js 'document.querySelector(".error")?.textContent')"

echo "== 6. Connect Google button goes to Google"
$B navigate http://localhost:8000/settings >/dev/null; $B wait '#save-prefs' >/dev/null; sleep 1
click_text "Connect Google Calendar" 3
echo "   now at: $($B get url | tail -1 | cut -c1-60)..."

echo "== 7. logout"
$B navigate http://localhost:8000/ >/dev/null; sleep 2; click_text "Log out" 2
echo "   now at: $($B get url | tail -1)"
echo "== console errors:"; $B console 2>&1 | grep "\[error\]" | grep -v favicon | tail -5
