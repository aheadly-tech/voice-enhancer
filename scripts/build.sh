#!/usr/bin/env bash
#
# Build everything: C++ DSP engine, HAL virtual driver bundle, and the
# SwiftUI app. Output lands in build/ at the repo root.
#
# Usage:
#     scripts/build.sh                # Release build
#     scripts/build.sh --debug        # Debug build with symbols
#     scripts/build.sh --engine-only  # Skip driver + app (quick iteration)
#
# Why a hand-written shell script rather than a top-level CMakeLists?
#   * The Swift app is built with Xcode, not CMake.
#   * Mixing a root CMake over three heterogeneous subprojects adds a
#     configuration layer for no benefit — each subproject already has its
#     own idiomatic build.
#
# Exits non-zero on the first failed step; CI treats that as a build break.

set -euo pipefail

# --- Locate the repo root regardless of where we're invoked from ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# --- Parse flags ----------------------------------------------------------
BUILD_TYPE="Release"
BUILD_ENGINE=1
BUILD_DRIVER=1
BUILD_APP=1
CMAKE_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)        BUILD_TYPE="Debug" ;;
        --engine-only)  BUILD_DRIVER=0; BUILD_APP=0 ;;
        --driver-only)  BUILD_ENGINE=0; BUILD_APP=0 ;;
        --no-app)       BUILD_APP=0 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown flag: $1" >&2
            exit 2
            ;;
    esac
    shift
done

# --- Platform guard -------------------------------------------------------
# The HAL driver and the Swift app are macOS-only. The C++ DSP engine
# builds on Linux (that's how CI runs tests), so we let engine-only builds
# through on non-macOS.
if [[ "$(uname)" != "Darwin" ]]; then
    if [[ $BUILD_DRIVER -eq 1 || $BUILD_APP -eq 1 ]]; then
        echo "error: the driver and app only build on macOS." >&2
        echo "       pass --engine-only to build just the DSP library." >&2
        exit 1
    fi
else
    # CMake can otherwise default to x86_64 on Apple Silicon when invoked
    # through a non-default compiler wrapper (for example ccache). Pin the
    # host architecture explicitly so the engine/driver match the app build.
    CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES="$(uname -m)")
fi

# --- Helpers --------------------------------------------------------------
log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
done_() { printf "\033[1;32m ok \033[0m %s\n" "$*"; }

# --- Step 1: AudioEngine (C++ DSP library) --------------------------------
if [[ $BUILD_ENGINE -eq 1 ]]; then
    log "Building AudioEngine ($BUILD_TYPE)"
    cmake -S AudioEngine -B AudioEngine/build \
          -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
          -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
          -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
          "${CMAKE_ARGS[@]}"
    cmake --build AudioEngine/build --parallel
    done_ "AudioEngine -> AudioEngine/build/libvoice_enhancer.a"

    # Quick sanity test. If unit tests regress, we want to fail the build
    # before wasting time on driver/app steps.
    if [[ -x AudioEngine/build/voice_enhancer_tests ]]; then
        log "Running AudioEngine tests"
        AudioEngine/build/voice_enhancer_tests
        done_ "AudioEngine tests passed"
    fi
fi

# --- Step 2: VirtualDriver (HAL bundle) -----------------------------------
if [[ $BUILD_DRIVER -eq 1 ]]; then
    log "Building VirtualDriver ($BUILD_TYPE)"
    cmake -S VirtualDriver -B VirtualDriver/build \
          -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
          -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
          "${CMAKE_ARGS[@]}"
    cmake --build VirtualDriver/build --parallel
    codesign --force --sign - --timestamp=none --deep \
        VirtualDriver/build/VoiceEnhancer.driver >/dev/null
    done_ "VirtualDriver -> VirtualDriver/build/VoiceEnhancer.driver"
fi

# --- Step 3: SwiftUI app --------------------------------------------------
if [[ $BUILD_APP -eq 1 ]]; then
    log "Building VoiceEnhancer.app ($BUILD_TYPE)"

    # The shipped app build is driven by an Xcode project. The project is
    # declarative (VoiceEnhancerApp/project.yml) and generated on demand
    # by XcodeGen — we don't check a hand-written .xcodeproj into the repo.
    #
    # Decision tree:
    #   * project.yml present + xcodegen available  -> generate + xcodebuild
    #   * project.yml present + xcodegen missing    -> hint, fall back to swift build
    #   * project.yml missing                       -> swift build (stub engine)
    if [[ -f VoiceEnhancerApp/project.yml ]] && command -v xcodegen >/dev/null 2>&1; then
        log "Generating Xcode project from VoiceEnhancerApp/project.yml"
        (cd VoiceEnhancerApp && xcodegen generate --quiet)
    elif [[ -f VoiceEnhancerApp/project.yml ]]; then
        echo "note: xcodegen not installed. 'brew install xcodegen' to enable the full app build." >&2
        echo "      falling back to 'swift build' (stub engine — no DSP, no driver routing)." >&2
    fi

    if [[ -f VoiceEnhancerApp/VoiceEnhancer.xcodeproj/project.pbxproj ]]; then
        XCODEBUILD_ARGS=(
            -project VoiceEnhancerApp/VoiceEnhancer.xcodeproj
            -scheme VoiceEnhancer
            -configuration "$BUILD_TYPE"
            -derivedDataPath VoiceEnhancerApp/build
            build
        )
        if command -v xcpretty >/dev/null 2>&1; then
            xcodebuild "${XCODEBUILD_ARGS[@]}" | xcpretty
        else
            xcodebuild "${XCODEBUILD_ARGS[@]}"
        fi
        done_ "VoiceEnhancer.app -> VoiceEnhancerApp/build/Build/Products/$BUILD_TYPE/"
    else
        echo "note: no Xcode project found; building Swift module only." >&2
        (cd VoiceEnhancerApp && swift build -c "$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')")
        done_ "Swift module built (stub engine path)"
    fi
fi

echo
done_ "Build complete."
