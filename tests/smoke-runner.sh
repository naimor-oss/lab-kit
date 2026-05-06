#!/usr/bin/env bash
# tests/smoke-runner.sh — exercise bin/run-scenario.sh's CLI surface
# without booting a VM. The runner is the contract every sibling
# wrapper depends on; this pins its argument parser, env-defaults
# behavior, and exit-code semantics.
#
# What this catches that a per-sibling lab cycle wouldn't:
#   - "I added a flag and forgot a `shift`" — wrong scenario file picked
#   - "I renamed --verify-only and didn't update the help text"
#   - "Missing scenario arg now silently runs verify-only on /tmp/junk"
#   - "Unknown flag exits 0 instead of 2" — silent test breakage
# A real lab cycle would catch these too, but ~10 minutes later and
# only after a VM revert. This catches them in <1 second.
#
# Usage:
#   bash tests/smoke-runner.sh         # exit 0 = pass; non-zero = first failure
#   VERBOSE=1 bash tests/smoke-runner.sh
#
# Adding a test: each test shells out to the runner with carefully
# chosen LAB_* env unset (so we DON'T accidentally hit a real lab
# host) and asserts (a) the exit code, (b) a fragment of stdout/stderr.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/../bin/run-scenario.sh"
[[ -x "$RUNNER" ]] || { echo "FAIL: runner not executable at $RUNNER" >&2; exit 2; }

PASS=0
FAIL=0
FIRST_FAIL=""

# Run the runner under a clean LAB_* env so we never accidentally
# trigger ssh against a real host. Capture stdout+stderr together;
# return the runner's exit code in a global so callers can assert.
run_runner() {
    LAST_OUT=$(env -i \
        HOME="$HOME" PATH="$PATH" \
        bash "$RUNNER" "$@" 2>&1)
    LAST_RC=$?
}

check_rc() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1))
        [[ "${VERBOSE:-0}" == "1" ]] && printf '  ok   %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %s\n' "$name"
        printf '  expected rc: %s\n' "$expected"
        printf '  actual rc:   %s\n' "$actual"
        printf '  output:      %s\n' "${LAST_OUT:-(empty)}" | head -5
        [[ -z "$FIRST_FAIL" ]] && FIRST_FAIL="$name"
    fi
}

check_contains() {
    local name="$1" needle="$2" haystack="$3"
    # `--` terminates option parsing. macOS BSD grep otherwise treats
    # a needle like '--no-stage' as a flag and emits its own usage.
    if grep -qF -- "$needle" <<< "$haystack"; then
        PASS=$((PASS + 1))
        [[ "${VERBOSE:-0}" == "1" ]] && printf '  ok   %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %s\n' "$name"
        printf '  expected to contain: %s\n' "$needle"
        printf '  output: %s\n' "$(echo "$haystack" | head -3)"
        [[ -z "$FIRST_FAIL" ]] && FIRST_FAIL="$name"
    fi
}

#-------------------------------------------------------------------------------
# Help / usage.
#-------------------------------------------------------------------------------
echo "== help / usage =="
run_runner --help
check_rc       "--help exits 0" 0 "$LAST_RC"
check_contains "--help mentions Usage:"     "Usage:"          "$LAST_OUT"
check_contains "--help mentions --no-stage" "--no-stage"      "$LAST_OUT"
check_contains "--help mentions --no-reset" "--no-reset"      "$LAST_OUT"
check_contains "--help mentions --no-push"  "--no-push"       "$LAST_OUT"
check_contains "--help mentions --verify-only" "--verify-only" "$LAST_OUT"
check_contains "--help mentions LAB_HV_HOST" "LAB_HV_HOST"    "$LAST_OUT"

run_runner -h
check_rc "-h exits 0 (alias for --help)" 0 "$LAST_RC"

#-------------------------------------------------------------------------------
# Missing / wrong arguments.
#-------------------------------------------------------------------------------
echo "== missing / wrong arguments =="

# No scenario file at all — should exit 2 with usage. NOT 0 (silent
# pass), NOT 1 (not a scenario failure), specifically 2 (CLI misuse).
run_runner
check_rc       "no args -> rc=2"           2 "$LAST_RC"
check_contains "no args prints Usage:"     "Usage:" "$LAST_OUT"

# Two scenario files — should exit 2 with a specific message.
run_runner /tmp/scenario-a.sh /tmp/scenario-b.sh
check_rc       "two scenarios -> rc=2"     2 "$LAST_RC"
check_contains "two scenarios message"     "Only one scenario" "$LAST_OUT"

# Unknown flag — must exit 2, not silently ignored.
run_runner --no-such-flag
check_rc       "unknown flag -> rc=2"      2 "$LAST_RC"
check_contains "unknown flag message"      "Unknown flag" "$LAST_OUT"

# A scenario file that doesn't exist on disk.
run_runner /this/does/not/exist.sh
check_rc       "missing scenario -> rc=2"  2 "$LAST_RC"
check_contains "missing scenario message"  "Scenario not found" "$LAST_OUT"

#-------------------------------------------------------------------------------
# Argument parser invariants — pin behaviors siblings rely on.
#-------------------------------------------------------------------------------
echo "== argument parser invariants =="

# A scenario file that exists but is empty. The runner should source
# it (no-op), then proceed to mkdir LAB_RESULTS_DIR + tee log. Without
# LAB_VM_NAME set and with --no-stage --no-reset --no-push, the
# pipeline reaches verify() which is the runner's default
# (rc=2, "verify() not defined"). The TEST: rc must be non-zero AND
# the output must mention "verify() not defined", proving the runner
# correctly fell through to its default verify() rather than crashing.
empty_scenario=$(mktemp /tmp/empty-scenario-XXXX.sh)
trap 'rm -f "$empty_scenario"' EXIT
: > "$empty_scenario"

run_runner --no-stage --no-reset --no-push "$empty_scenario"
# rc=1 because verify() returned 2, runner caught it and reports FAIL.
# We tolerate rc=1 (verify failed) but NOT rc=0 (silent pass) or rc=2
# (which would mean it didn't even reach verify).
[[ "$LAST_RC" == "1" ]]
check_rc "empty scenario reaches verify() default -> rc=1" 0 $?
check_contains "empty scenario hits default verify()"  "verify() not defined" "$LAST_OUT"

# --verify-only with an empty scenario should ALSO reach the default
# verify() and exit 1. Specifically it must NOT try to ssh anywhere,
# which would fail with a different error before hitting verify.
run_runner --verify-only "$empty_scenario"
check_contains "--verify-only with empty scenario reaches verify()"  "verify() not defined" "$LAST_OUT"
# Stronger pin: --verify-only MUST skip pre_hook and run_scenario. If
# someone breaks --verify-only to leave VERIFY_ONLY=0, the runner
# would emit the "pre_hook" / "scenario body" step banners. Their
# absence here proves the skip happened.
[[ "$LAST_OUT" != *"=== pre_hook"* ]]
check_rc "--verify-only skips pre_hook" 0 $?
[[ "$LAST_OUT" != *"=== scenario body"* ]]
check_rc "--verify-only skips run_scenario" 0 $?

# A scenario file that defines verify() returning 0 should exit 0 with
# --verify-only. This is the green-path smoke for the verify branch.
ok_scenario=$(mktemp /tmp/ok-scenario-XXXX.sh)
trap 'rm -f "$empty_scenario" "$ok_scenario"' EXIT
cat > "$ok_scenario" <<'EOF'
verify() { return 0; }
EOF
run_runner --verify-only "$ok_scenario"
check_rc       "verify=0 with --verify-only -> rc=0" 0 "$LAST_RC"
check_contains "verify=0 reports PASS"               "PASS" "$LAST_OUT"

# A scenario that defines verify() returning 1 should exit 1.
fail_scenario=$(mktemp /tmp/fail-scenario-XXXX.sh)
trap 'rm -f "$empty_scenario" "$ok_scenario" "$fail_scenario"' EXIT
cat > "$fail_scenario" <<'EOF'
verify() { return 1; }
EOF
run_runner --verify-only "$fail_scenario"
check_rc       "verify=1 with --verify-only -> rc=1" 1 "$LAST_RC"
check_contains "verify=1 reports FAIL"               "FAIL" "$LAST_OUT"

#-------------------------------------------------------------------------------
# Latent-bug regression: the runner's outer rc must be non-zero when
# the scenario aborts on a ${VAR:?} parameter check. Until 2026-05-06
# the outer rc was 0 in this case (the EXIT trap's last command was
# the say-echo, which succeeded; the wait-for-tee in `exec >` returned
# 0; bash's "last command" became the trap's echo and rc=0 was
# returned). Catastrophic failures looked like silent successes to
# anyone scripting around `lab/run-scenario.sh && next-step`.
#
# Trigger: pass --no-stage --no-push but NOT --no-reset, with
# LAB_VM_NAME unset. The reset step does
# `: "${LAB_VM_NAME:?LAB_VM_NAME required for reset}"` and aborts.
# Outer rc MUST be non-zero. Trap's EXIT line should also appear.
#-------------------------------------------------------------------------------
echo '== ${VAR:?} abort propagates rc =='

run_runner --no-stage --no-push "$ok_scenario"
[[ "$LAST_RC" -ne 0 ]]
check_rc "init-abort gives non-zero outer rc" 0 $?
check_contains "init-abort prints the EXIT trap line"   "EXIT rc="          "$LAST_OUT"
check_contains "init-abort mentions LAB_VM_NAME"        "LAB_VM_NAME"       "$LAST_OUT"

#-------------------------------------------------------------------------------
echo
echo "summary: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
    echo "first failure: $FIRST_FAIL"
    exit 1
fi
exit 0
