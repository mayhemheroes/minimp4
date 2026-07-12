#!/usr/bin/env bash
#
# mayhem/build.sh — build minimp4's fuzz harness + the standalone reproducer + the functional
# oracle. minimp4 is a single-header library (minimp4.h); minimp4_test.c is the upstream CLI
# driver + the project's own known-answer test suite (scripts/test.sh compares its output against
# committed golden vectors).
#
# Produces:
#   /mayhem/fuzz_minimp4              libFuzzer target (sanitized library + harness) -> minimp4-x86
#   /mayhem/fuzz_minimp4-standalone   run-once reproducer (no libFuzzer runtime)
#   /mayhem/build-oracle/minimp4_x86  clean (NORMAL flags) CLI binary for mayhem/test.sh
#
# Everything comes from the two upstream files (minimp4.h + minimp4_test.c) — no network, no
# upstream edits; re-runnable/air-gapped (idempotent).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the environment (base image exports the defaults); fall back for a bare run.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

HARNESS="mayhem/fuzz_minimp4.c"
# minimp4.h is header-only and #included (with MINIMP4_IMPLEMENTATION) by the harness, so compiling
# the harness with $SANITIZER_FLAGS instruments the FUZZED library code itself (not just the driver).
# -D_FILE_OFFSET_BITS=64 matches upstream's build flags. $DEBUG_FLAGS after the sanitizer flags so
# -gdwarf-3 wins (DWARF must be < 4 for Mayhem triage).

# 1) libFuzzer target — the Mayhem target `minimp4-x86`.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    -D_FILE_OFFSET_BITS=64 -I. \
    "$HARNESS" -o /mayhem/fuzz_minimp4 -lm

# 2) Standalone run-once reproducer (no libFuzzer runtime): same harness linked against the
#    base image's $STANDALONE_FUZZ_MAIN driver.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS \
    -D_FILE_OFFSET_BITS=64 -I. \
    "$STANDALONE_FUZZ_MAIN" "$HARNESS" -o /mayhem/fuzz_minimp4-standalone -lm

# 3) Clean oracle build (NO sanitizers) so mayhem/test.sh stays an honest functional oracle that
#    won't false-fail on benign UB. Same flags as upstream scripts/build_x86.sh (minus -flto, which
#    slows the build and is irrelevant to correctness). $COVERAGE_FLAGS is empty unless a coverage
#    build requests it.
mkdir -p build-oracle
# shellcheck disable=SC2086
$CC -O2 $COVERAGE_FLAGS -std=gnu11 -DNDEBUG -D_FILE_OFFSET_BITS=64 \
    -o build-oracle/minimp4_x86 minimp4_test.c -lm -lpthread

echo "build.sh: built /mayhem/fuzz_minimp4 (+ -standalone) and build-oracle/minimp4_x86 (oracle)"
