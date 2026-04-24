#!/usr/bin/env bash
#
# Remove the HAL driver bundle and clean up the shared-memory ring.
#
# Usage:
#     sudo scripts/uninstall.sh
#
# After running this:
#   * /Library/Audio/Plug-Ins/HAL/VoiceEnhancer.driver is gone.
#   * coreaudiod has been restarted so the device disappears from Audio
#     MIDI Setup and from the system's device list.
#   * The POSIX shared-memory segment is unlinked (harmless if already gone).
#
# The app bundle itself (~/Applications/Voice Enhancer.app or wherever the
# user dropped it) is not touched — that's a GUI drag to Trash.

set -euo pipefail

HAL_DIR="/Library/Audio/Plug-Ins/HAL"
BUNDLE_NAME="VoiceEnhancer.driver"
DEST="$HAL_DIR/$BUNDLE_NAME"
SHM_NAME="/ve.aheadly.r1"   # keep in sync with RingBuffer.h

log()   { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m ok \033[0m %s\n" "$*"; }
fatal() { printf "\033[1;31merr\033[0m %s\n" "$*" >&2; exit 1; }

if [[ "$(uname)" != "Darwin" ]]; then
    fatal "This script is macOS-only."
fi

if [[ $EUID -ne 0 ]]; then
    fatal "Needs root. Re-run with: sudo $0"
fi

# --- Remove the bundle ----------------------------------------------------

if [[ -d "$DEST" ]]; then
    log "Removing $DEST"
    rm -rf "$DEST"
    ok "Bundle removed"
else
    ok "Bundle not present at $DEST (already uninstalled)"
fi

# --- Unlink shared memory -------------------------------------------------
#
# /dev/shm doesn't exist on macOS — POSIX shared memory lives inside a
# private kernel space. shm_unlink is the only clean way to remove it, and
# there's no CLI shipped with macOS. We call a tiny inline helper.
#
# This is a no-op if the segment was never created.

log "Unlinking shared-memory segment $SHM_NAME"
# Fork a Python one-liner because that's by far the shortest path to
# shm_unlink without shipping a helper binary. Both Python 2 and 3 on
# macOS include the posix module; `import posix; posix.shm_unlink(...)`
# only exists in Python 3.8+ — we use a ctypes call for portability.
/usr/bin/python3 - "$SHM_NAME" <<'PY' || true
import ctypes, ctypes.util, sys, os
libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
libc.shm_unlink.argtypes = [ctypes.c_char_p]
libc.shm_unlink.restype  = ctypes.c_int
rc = libc.shm_unlink(sys.argv[1].encode("utf-8"))
if rc != 0 and ctypes.get_errno() != 2:   # ENOENT is fine
    print(f"shm_unlink failed: errno={ctypes.get_errno()}", file=sys.stderr)
PY
ok "Shared memory cleaned"

# --- Restart coreaudiod ---------------------------------------------------

log "Restarting coreaudiod"
killall -9 coreaudiod 2>/dev/null || true
sleep 1
ok "coreaudiod restarted"

echo
ok "Uninstall complete."
