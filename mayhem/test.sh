#!/usr/bin/env bash
#
# mayhem/test.sh — functional oracle for minimp4. RUNS the prebuilt clean CLI binary
# (build-oracle/minimp4_x86 from mayhem/build.sh) through the PROJECT'S OWN upstream test suite
# (the known-answer comparisons in upstream scripts/test.sh): mux the sample H.264 streams and
# demux the sample MP4s, asserting each output is byte-identical to the committed golden vector.
#
# This is the project's existing suite (tests_found = these 7 KAT cases), NOT an invented oracle —
# the ARM/qemu leg of upstream scripts/test.sh is intentionally skipped (no cross-toolchain in the
# commit image; recorded as skipped). It is behavioral: a PATCH that neuters minimp4 to exit(0)
# emits no/incorrect output and FAILS here (anti-reward-hack). Emits a CTRF report; exits nonzero
# iff any case failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

BIN=build-oracle/minimp4_x86
VEC="$SRC/vectors"
WORK=/tmp/minimp4_test
passed=0; failed=0; skipped=1   # skipped: the qemu-arm leg of upstream scripts/test.sh

check() { # <name> <rc>
  if [ "$2" -eq 0 ]; then echo "  ok   - $1"; passed=$((passed+1))
  else echo "  FAIL - $1"; failed=$((failed+1)); fi
}

# emit_ctrf <tool> <passed> <failed> [skipped]
emit_ctrf() {
  local tool="$1" p="$2" f="$3" s="${4:-0}"
  local tests=$(( p + f + s ))
  cat > "${CTRF_REPORT:-${SRC:-/mayhem}/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $p, "failed": $f, "pending": 0, "skipped": $s, "other": 0 }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$p" "$f" "$s"
}

if [ ! -x "$BIN" ]; then
  echo "test.sh: $BIN missing — build.sh must build it (not rebuilding here)" >&2
  emit_ctrf minimp4 0 1 0; exit 1
fi

rm -rf "$WORK"; mkdir -p "$WORK"

# mux_case <name> <flags> <input.264> <golden.mp4>
mux_case() {
  local name="$1" flags="$2" in="$3" golden="$4" out="$WORK/${1}.mp4"
  # shellcheck disable=SC2086
  "$SRC/$BIN" $flags "$VEC/$in" "$out" >/dev/null 2>&1
  if [ -f "$out" ] && cmp -s "$out" "$VEC/$golden"; then check "$name" 0; else check "$name" 1; fi
}

# demux_case <name> <input.mp4> <golden.264>
demux_case() {
  local name="$1" in="$2" golden="$3" out="$WORK/${1}.h264"
  "$SRC/$BIN" -d "$VEC/$in" "$out" >/dev/null 2>&1
  if [ -f "$out" ] && cmp -s "$out" "$VEC/$golden"; then check "$name" 0; else check "$name" 1; fi
}

mux_case   "mux"                ""   foreman.264        out_ref.mp4
mux_case   "mux_sequential"     "-s" foreman.264        out_sequential_ref.mp4
mux_case   "mux_fragmentation"  "-f" foreman.264        out_fragmentation_ref.mp4
mux_case   "mux_slices"         ""   foreman_slices.264 out_slices_ref.mp4
demux_case "demux"              out_ref.mp4            foreman.264
demux_case "demux_sequential"   out_sequential_ref.mp4 foreman.264
demux_case "demux_slices"       out_slices_ref.mp4     foreman_slices.264

echo "test.sh: passed=$passed failed=$failed skipped=$skipped"
emit_ctrf minimp4 "$passed" "$failed" "$skipped"
[ "$failed" -eq 0 ]
