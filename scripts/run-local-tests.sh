#!/bin/bash
# Run the entry module's local (host) hypium unit tests and FAIL on any
# assertion failure.
#
# Why this exists: `hvigorw ... test` executes the assertions but reports
# BUILD SUCCESSFUL even when an `expect().assertX()` fails — the failure only
# appears as an `ERROR: Error in <case>, ...` / `AssertException` line in the
# log, not in the exit code. Relying on BUILD SUCCESSFUL alone lets a broken
# test pass silently. This wrapper greps the output for those failure lines and
# exits non-zero if any are present, giving a trustworthy pass/fail signal.
set -u

export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
export DEVECO_NODE_HOME="${DEVECO_NODE_HOME:-/Applications/DevEco-Studio.app/Contents/tools/node}"
HVIGORW="${HVIGORW:-/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="$("$HVIGORW" --mode module -p module=entry@default -p isLocalTest=true test 2>&1)"
echo "$OUT"

echo "$OUT" | grep -qiE "BUILD SUCCESSFUL" || {
  echo ""
  echo "LOCAL TESTS: FAIL (build did not succeed)"
  exit 1
}

FAILS="$(echo "$OUT" | grep -icE "ERROR: Error in|AssertException")"
if [ "$FAILS" -ne 0 ]; then
  echo ""
  echo "LOCAL TESTS: FAIL ($FAILS assertion-failure line(s) — see 'ERROR: Error in ...' above)"
  exit 1
fi

echo ""
echo "LOCAL TESTS: PASS (build succeeded, 0 assertion failures)"
