#!/usr/bin/env bash
#
# mayhem/test.sh — run json.h's own utest suite (test/*.c, test/*.cpp, built by mayhem/build.sh into
# build/tests/json_test) and report CTRF counts. The suite asserts parsed values, error codes and
# exact writer output, so a neutered parser/writer fails it.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

runner="$SRC/build/tests/json_test"
if [ ! -x "$runner" ]; then
  echo "test.sh: $runner missing — mayhem/build.sh should have built it" >&2
  emit_ctrf "utest" 0 1 0
  exit 1
fi

out="$("$runner" 2>&1)"; rc=$?
printf '%s\n' "$out" | tail -n 5

# utest prints one line per test: "[       OK ] name", "[  FAILED  ] name (...)", "[  SKIPPED ] name (...)",
# plus "[==========] N test cases ran." Count the per-test lines; anything that ran but is not OK counts failed.
clean="$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g')"
ran=$(printf '%s\n' "$clean" | sed -n 's/^\[==========\] \([0-9]*\) test cases ran\.$/\1/p' | tail -n1)
passed=$(printf '%s\n' "$clean" | grep -c '^\[       OK \] ')
skipped=$(printf '%s\n' "$clean" | grep -cE '^\[  SKIPPED \] .*\([0-9]+')
ran=${ran:-0}
failed=$(( ran - passed - skipped ))
if [ "$ran" -eq 0 ] || [ "$rc" -ne 0 ]; then
  [ "$failed" -gt 0 ] || failed=1
fi
emit_ctrf "utest" "$passed" "$failed" "$skipped"
