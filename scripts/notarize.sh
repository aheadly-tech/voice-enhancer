#!/usr/bin/env bash
#
# Sign, notarize, and staple the Voice Enhancer app and HAL driver.
#
# This script assumes you already have:
#   * A Developer ID Application certificate in your login keychain.
#   * An app-specific password stored in the keychain under the profile
#     name given by NOTARY_PROFILE below (create once with `xcrun notarytool
#     store-credentials`).
#
# Usage:
#     scripts/notarize.sh path/to/VoiceEnhancer.app path/to/VoiceEnhancer.driver
#
# Or with environment overrides:
#     DEVELOPER_ID="Developer ID Application: Your Team (ABC1234567)" \
#     NOTARY_PROFILE="aheadly-notary" \
#     scripts/notarize.sh ...
#
# The HAL driver is a separate, independently-loaded bundle — coreaudiod
# does its own Gatekeeper check on it. That means it must be signed and
# notarized in its own right. We can't just sign the app and call it done.

set -euo pipefail

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-aheadly-notary}"
ENTITLEMENTS_APP="${ENTITLEMENTS_APP:-$(dirname "$0")/../VoiceEnhancerApp/Sources/Resources/VoiceEnhancer.entitlements}"

log()   { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m ok \033[0m %s\n" "$*"; }
fatal() { printf "\033[1;31merr\033[0m %s\n" "$*" >&2; exit 1; }

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <VoiceEnhancer.app> [VoiceEnhancer.driver]" >&2
    exit 2
fi

APP_PATH="$1"
DRIVER_PATH="${2:-}"

if [[ -z "$DEVELOPER_ID" ]]; then
    # Try to auto-detect a Developer ID cert. Ambiguous if the keychain
    # has more than one — in that case the user must pass it explicitly.
    DEVELOPER_ID="$(security find-identity -v -p codesigning | \
        awk -F'"' '/Developer ID Application/ {print $2; exit}')"
    if [[ -z "$DEVELOPER_ID" ]]; then
        fatal "No Developer ID Application cert found. Set DEVELOPER_ID env var."
    fi
    log "Using auto-detected identity: $DEVELOPER_ID"
fi

sign_and_verify() {
    local target="$1"
    local entitlements_arg=()
    if [[ -n "${2:-}" && -f "$2" ]]; then
        entitlements_arg=(--entitlements "$2")
    fi

    log "Signing $target"
    codesign --force --deep --strict \
             --options runtime \
             --timestamp \
             --sign "$DEVELOPER_ID" \
             "${entitlements_arg[@]}" \
             "$target"

    log "Verifying signature on $target"
    codesign --verify --deep --strict --verbose=2 "$target"
    ok "Signature valid: $target"
}

notarize_and_staple() {
    local target="$1"
    local zip_tmp
    zip_tmp="$(mktemp -d)/$(basename "$target").zip"

    log "Packaging $target for upload"
    ditto -c -k --keepParent "$target" "$zip_tmp"

    log "Submitting to notary service"
    xcrun notarytool submit "$zip_tmp" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    log "Stapling ticket to $target"
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
    ok "Notarized and stapled: $target"
}

# --- App -----------------------------------------------------------------

sign_and_verify "$APP_PATH" "$ENTITLEMENTS_APP"
notarize_and_staple "$APP_PATH"

# --- HAL driver (optional second arg) ------------------------------------

if [[ -n "$DRIVER_PATH" ]]; then
    # The HAL driver doesn't use an entitlements file — it runs inside
    # coreaudiod's sandbox and inherits it.
    sign_and_verify "$DRIVER_PATH"
    notarize_and_staple "$DRIVER_PATH"
fi

echo
ok "All artifacts signed, notarized, and stapled."
