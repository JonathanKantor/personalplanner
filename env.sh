# Source this before running jac in this project:  source env.sh
#
# Workaround: the jac 0.37.14 binary bundles a Python whose XML module links
# against macOS's /usr/lib/libexpat, which is too old on macOS 14.2.1
# (missing _XML_SetAllocTrackerActivationThreshold). Without this, pip can't
# run inside .jac/venv and `jac install` fails with "No module named pip".
# Homebrew's expat (brew install expat) provides the newer library.
if [ -d /opt/homebrew/opt/expat/lib ]; then
    export DYLD_LIBRARY_PATH="/opt/homebrew/opt/expat/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
else
    echo "env.sh: Homebrew expat not found; run: brew install expat" >&2
fi

# `jac run` does not read .env by itself (verified), so export its variables
# (e.g. GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET) into this shell.
if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi
