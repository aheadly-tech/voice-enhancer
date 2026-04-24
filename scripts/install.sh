#!/usr/bin/env bash
#
# Install the HAL driver bundle into /Library/Audio/Plug-Ins/HAL and
# restart coreaudiod so it picks up the new plugin.
#
# Usage:
#     sudo scripts/install.sh
#
# Why sudo? /Library/Audio/Plug-Ins/HAL is owned by root:wheel and that's
# the only directory coreaudiod (also running as root) scans for plugins.
# There's no user-scope equivalent on modern macOS.
#
# Safe to re-run. This script is idempotent: any existing
# VoiceEnhancer.driver at the target path is removed first, then replaced.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HAL_DIR="/Library/Audio/Plug-Ins/HAL"
BUNDLE_NAME="VoiceEnhancer.driver"
DEST="$HAL_DIR/$BUNDLE_NAME"

log()   { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m ok \033[0m %s\n" "$*"; }
fatal() { printf "\033[1;31merr\033[0m %s\n" "$*" >&2; exit 1; }

# --- Preconditions --------------------------------------------------------

if [[ "$(uname)" != "Darwin" ]]; then
    fatal "Voice Enhancer only installs on macOS."
fi

if [[ $EUID -ne 0 ]]; then
    fatal "This script needs root. Re-run with: sudo $0"
fi

# Locate the built bundle. Try the standard CMake output first, then fall
# back to an xcodebuild output if someone wired that up.
BUNDLE_SRC=""
CANDIDATES=(
    "$REPO_ROOT/VirtualDriver/build/$BUNDLE_NAME"
    "$REPO_ROOT/build/$BUNDLE_NAME"
)
for c in "${CANDIDATES[@]}"; do
    if [[ -d "$c" ]]; then
        BUNDLE_SRC="$c"
        break
    fi
done

if [[ -z "$BUNDLE_SRC" ]]; then
    fatal "Couldn't find $BUNDLE_NAME. Run scripts/build.sh first."
fi

# --- Remove any existing install -----------------------------------------

if [[ -d "$DEST" ]]; then
    log "Removing existing $DEST"
    rm -rf "$DEST"
fi

# --- Copy bundle ----------------------------------------------------------

log "Installing $BUNDLE_NAME to $HAL_DIR"
mkdir -p "$HAL_DIR"
cp -R "$BUNDLE_SRC" "$DEST"

# HAL plugins must be owned by root for coreaudiod to load them. The copy
# inherits the current user — fix it explicitly.
chown -R root:wheel "$DEST"
chmod -R go-w "$DEST"

ok "Bundle installed at $DEST"

# --- Kick coreaudiod ------------------------------------------------------
#
# coreaudiod scans HAL plugins at startup. Killing it tells launchd to
# restart the daemon, which re-scans the directory. This momentarily
# interrupts system audio — nothing bad, but worth mentioning.

log "Restarting coreaudiod (brief audio interruption)"
killall -9 coreaudiod 2>/dev/null || true
sleep 1

# Give the daemon a beat to re-register. A harder check would be to list
# devices via system_profiler, but that's ~1s more and this is good enough.
ok "coreaudiod restarted"

echo
ok "Install complete. Open the Voice Enhancer app and 'Voice Enhancer'"
echo "   should now appear as a microphone in your recording apps."
