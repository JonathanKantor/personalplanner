#!/bin/bash
# Apply the jac 0.37.14 native-runtime workaround to the generated Expo project.
# Run once after `jac setup mobile` (and again if you delete .jac/mobile-rn):
#     bash scripts/fix_mobile_native.sh
# See mobile/native-fix/jac_runtime_shim.js for what it fixes.
set -e
cd "$(dirname "$0")/.."
RN=.jac/mobile-rn
if [ ! -f "$RN/metro.config.js" ]; then
    echo "No $RN/metro.config.js - run: source env.sh && jac setup mobile" >&2
    exit 1
fi
mkdir -p "$RN/jac-shim"
cp mobile/native-fix/jac_runtime_shim.js "$RN/jac-shim/runtime.js"
python3 - "$RN/metro.config.js" <<'EOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
# Removing this marker line tells Jac not to regenerate (and undo) the file.
t = t.replace("// jac-client: scaffold-managed; remove this line to opt out of auto-refresh\n", "")
old = "'@jac/runtime': path.resolve(projectRoot, 'jac-src', 'client_runtime.js'),"
new = "'@jac/runtime': path.resolve(projectRoot, 'jac-shim', 'runtime.js'),  // jac 0.37.14 fix: adds useJacState"
if new not in t:
    if old not in t:
        sys.exit("metro.config.js layout changed; apply the alias by hand (see this script)")
    t = t.replace(old, new)
p.write_text(t)
EOF
echo "Patched $RN: @jac/runtime -> jac-shim/runtime.js (adds useJacState)."
echo "Now: source env.sh && jac run --dev mobile   (then reload the app in Expo Go)"
