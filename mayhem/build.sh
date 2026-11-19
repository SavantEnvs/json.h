#!/usr/bin/env bash
#
# mayhem/build.sh — build json.h's fuzz harnesses and its own utest suite.
#
# json.h is a single header: the parser/writer implementation is compiled into each harness TU, so
# compiling the harness with $SANITIZER_FLAGS instruments the project code itself.
#   /mayhem/jsonh-fuzz        json_parse() with default flags (ported from mayhemheroes/json.h)
#   /mayhem/jsonh-roundtrip   json_parse_ex() under input-chosen flags + writers + extract + re-parse
# Each also gets a /mayhem/<t>-standalone run-once reproducer. The upstream test suite (test/,
# CMake + utest) is built with the project's normal flags into build/tests (gitignored).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"

OBJ="$SRC/build/fuzz"
mkdir -p "$OBJ"

# LeakSanitizer off at build time (SPEC §6.2 item 15); ASan + UBSan stay fully active.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OBJ/lsan_off.o"
# Standalone driver as a C object.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"

for t in jsonh-fuzz jsonh-roundtrip; do
  # Fuzzer: compile the harness (and with it all of json.h) with the engine flag so SanitizerCoverage
  # instruments the parser/writer code, not only the link.
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -I"$SRC" "$SRC/mayhem/$t.c" \
    "$OBJ/lsan_off.o" -lstdc++ -o "$SRC/$t"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -I"$SRC" "$OBJ/standalone_main.o" "$SRC/mayhem/$t.c" \
    "$OBJ/lsan_off.o" -o "$SRC/$t-standalone"
done

# Upstream's own test suite with its normal flags (no sanitizers from the fuzz build; COVERAGE_FLAGS
# is empty by default). Only the plain json_test target is built — the sanitizer variants upstream's
# CMakeLists also registers are not needed for the oracle.
env -u CFLAGS -u CXXFLAGS -u LDFLAGS \
  cmake -S "$SRC/test" -B "$SRC/build/tests" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS"
cmake --build "$SRC/build/tests" -j"$MAYHEM_JOBS" --target json_test
