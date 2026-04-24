cmake_minimum_required(VERSION 3.20)
project(voice_enhancer_engine
    VERSION 0.1.0
    DESCRIPTION "Voice Enhancer DSP engine"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Strict warnings. We do not ship warnings.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(
        -Wall -Wextra -Wpedantic
        -Wshadow -Wconversion -Wsign-conversion
        -Wnon-virtual-dtor -Wold-style-cast
        -Woverloaded-virtual -Wnull-dereference
        -Wdouble-promotion -Wformat=2
    )
endif()

# -----------------------------------------------------------------------------
# Main library: libvoice_enhancer
# -----------------------------------------------------------------------------
add_library(voice_enhancer STATIC
    src/Engine.cpp
    src/Preset.cpp
    src/dsp/Biquad.cpp
    src/dsp/HighPassFilter.cpp
    src/dsp/Compressor.cpp
    src/dsp/ParametricEQ.cpp
    src/dsp/DeEsser.cpp
    src/dsp/Limiter.cpp
    bridge/engine_c_api.cpp
)

target_include_directories(voice_enhancer
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/bridge>
)

# Position-independent so it can be embedded in a .dylib or app bundle later.
set_target_properties(voice_enhancer PROPERTIES
    POSITION_INDEPENDENT_CODE ON
)

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------
option(VOICE_ENHANCER_BUILD_TESTS "Build unit tests" ON)
if(VOICE_ENHANCER_BUILD_TESTS)
    add_executable(voice_enhancer_tests tests/test_engine.cpp)
    target_link_libraries(voice_enhancer_tests PRIVATE voice_enhancer)

    enable_testing()
    add_test(NAME engine_tests COMMAND voice_enhancer_tests)
endif()
