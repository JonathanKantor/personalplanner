#!/bin/bash
# Run the mobile app on a phone with Expo Go:   bash scripts/phone_dev.sh
#
# Why not just `jac run --dev mobile`: in jac 0.37.14 that command starts its
# API backend by "starting" the mobile app, which means building an Android
# APK (Gradle). Without the Android SDK that fails ("Invalid or corrupt
# jarfile ... gradle-wrapper.jar"), so the phone has no server to talk to and
# login/signup fail. Metro still serves the app, which is why it renders.
#
# That failed build also blanks .jac/mobile-rn/__jacApiBase.js, the file that
# tells the app where the API is (app.json keeps a copy, which the app falls
# back to).
#
# This script runs the real API ourselves (the web app's server, which also
# runs the mobile_api walkers) on the port the mobile dev server tells the
# phone to use, and restores __jacApiBase.js. You'll still see that Gradle
# error once in the output; ignore it.
#
# Prereqs (one time): jac setup mobile && bash scripts/fix_mobile_native.sh
# Phone and laptop must be on the same network (a phone hotspot works).
cd "$(dirname "$0")/.." || exit 1
source ./env.sh
PORT=${PORT:-8000}
APIBASE=.jac/mobile-rn/__jacApiBase.js

if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $PORT is busy; stop the other server or run: PORT=8010 bash scripts/phone_dev.sh" >&2
    exit 1
fi

# The mobile dev server writes the phone's API URL into $APIBASE at startup
# and picks another port if $PORT is taken, so it must start first. Once the
# URL is written, start the API server on that port in the background.
(
    for _ in $(seq 1 120); do
        grep -q "http://" "$APIBASE" 2>/dev/null && break
        sleep 1
    done
    sleep 2
    # Flags go BEFORE the app name (jac ignores them after it).
    jac run --port "$PORT" --no-client web < /dev/null > .jac/phone_api.log 2>&1 &
    echo "$!" > .jac/phone_api.pid
    for _ in $(seq 1 60); do
        curl -s -o /dev/null "http://localhost:$PORT/healthz" && break
        sleep 1
    done
    # Restore the API URL that the failed Android build blanked out
    # (Metro notices the change and reloads the app).
    URL=$(python3 -c "import json; print(json.load(open('.jac/mobile-rn/app.json'))['expo']['extra']['apiBaseUrl'])")
    echo "globalThis.__JAC_API_BASE_URL__ = \"$URL\";" > "$APIBASE"
    echo ""
    echo ">>> Planner API ready on port $PORT (log: .jac/phone_api.log)."
    echo ">>> The phone will use $URL - open the app in Expo Go (reload if it was open)."
) &

stop_api() {
    [ -f .jac/phone_api.pid ] && kill "$(cat .jac/phone_api.pid)" 2>/dev/null
    rm -f .jac/phone_api.pid
}
trap stop_api EXIT

jac run --dev --api-port "$PORT" mobile
