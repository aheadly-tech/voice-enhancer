cmake_minimum_required(VERSION 3.20)
project(voice_enhancer_driver
    VERSION 0.1.0
    DESCRIPTION "Voice Enhancer Core Audio HAL plugin"
    LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# -----------------------------------------------------------------------------
# Bundle target: VoiceEnhancer.driver
# -----------------------------------------------------------------------------
#
# A HAL plugin is a loadable bundle (MH_BUNDLE), packaged as a .driver folder
# with an Info.plist and the compiled binary inside. CMake's MACOSX_BUNDLE
# target property gets us most of the way; the .driver extension and the
# exact directory layout are finished by setting BUNDLE_EXTENSION.
# -----------------------------------------------------------------------------

set(DRIVER_SOURCES
    src/Plugin.cpp
    src/Device.cpp
    src/Stream.cpp
    src/ObjectRegistry.cpp
    src/Entry.cpp
)

add_library(VoiceEnhancer MODULE ${DRIVER_SOURCES})

set_target_properties(VoiceEnhancer PROPERTIES
    BUNDLE                 TRUE
    BUNDLE_EXTENSION       "driver"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    OUTPUT_NAME            "VoiceEnhancer"
    PREFIX                 ""
    SUFFIX                 ""
)

target_include_directories(VoiceEnhancer PRIVATE
    src
    ${CMAKE_CURRENT_SOURCE_DIR}/../shared
)

target_compile_options(VoiceEnhancer PRIVATE
    -Wall -Wextra -Wpedantic -Wshadow
    -fvisibility=hidden
)

# Hide everything except the single CFPlugIn factory function. HAL plugins
# load into coreaudiod — any symbol we export is added to that very busy
# namespace. Belt-and-braces: the one symbol we need exposed is already
# marked visible in Entry.cpp.
set_target_properties(VoiceEnhancer PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

# Core Audio frameworks.
find_library(COREAUDIO_LIB    CoreAudio    REQUIRED)
find_library(COREFOUNDATION_LIB CoreFoundation REQUIRED)
find_library(AUDIOTOOLBOX_LIB AudioToolbox REQUIRED)

target_link_libraries(VoiceEnhancer PRIVATE
    ${COREAUDIO_LIB}
    ${COREFOUNDATION_LIB}
    ${AUDIOTOOLBOX_LIB}
)

# -----------------------------------------------------------------------------
# Installation
# -----------------------------------------------------------------------------
# `make install` drops the bundle in /Library/Audio/Plug-Ins/HAL/. Requires
# sudo. Normally we don't want to touch system directories from CMake, but
# there's no other reasonable destination for a HAL plugin.
# -----------------------------------------------------------------------------

install(TARGETS VoiceEnhancer
    DESTINATION /Library/Audio/Plug-Ins/HAL
)
