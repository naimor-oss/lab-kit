#!/usr/bin/env bash
#
# Generic appliance lab scenario runner.
#
# Pipeline (each step is skippable via a flag):
#   stage  -> copy LAB_STAGE_SOURCES globs into LAB_STAGE_DIR
#             (host-side share where the hypervisor helper scripts live)
#   reset  -> revert LAB_VM_NAME to LAB_GOLDEN_CHECKPOINT via
#             Revert-TestVM.ps1 staged at LAB_STAGE_DIR
#   push   -> scp LAB_PUSH_FILES into the appliance's LAB_REMOTE_PUSH_DIR
#   post_push_cmd -> optional remote command (e.g. install binary)
#   pre_hook     -> scenario-defined
#   run_scenario -> scenario-defined
#   verify       -> scenario-defined
#   post_hook    -> scenario-defined
#
# Appliance-specific wiring lives in the LAB_ENV file and in the scenario
# file. The runner stays generic.

set -euo pipefail

LAB_ENV="${LAB_ENV:-}"
if [[ -n "$LAB_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$LAB_ENV"
fi

LAB_NAME="${LAB_NAME:-lab}"
LAB_RESULTS_DIR="${LAB_RESULTS_DIR:-test-results}"
LAB_STAGE_DIR="${LAB_STAGE_DIR:-}"
LAB_STAGE_SOURCES="${LAB_STAGE_SOURCES:-}"
LAB_HV_HOST="${LAB_HV_HOST:-server}"
LAB_HV_USER="${LAB_HV_USER:-nmadmin}"
LAB_VM_NAME="${LAB_VM_NAME:-}"
LAB_VM_IP="${LAB_VM_IP:-}"
LAB_VM_USER="${LAB_VM_USER:-}"
LAB_GOLDEN_CHECKPOINT="${LAB_GOLDEN_CHECKPOINT:-golden-image}"
LAB_REMOTE_PUSH_DIR="${LAB_REMOTE_PUSH_DIR:-/tmp}"
LAB_PUSH_FILES="${LAB_PUSH_FILES:-}"
LAB_POST_PUSH_CMD="${LAB_POST_PUSH_CMD:-}"

usage() {
    cat <<USAGE
Usage: LAB_ENV=.env $0 <scenario-file> [flags]

Flags:
  --no-stage      skip copying LAB_STAGE_SOURCES to LAB_STAGE_DIR
  --no-reset      skip VM checkpoint revert
  --no-push       skip LAB_PUSH_FILES copy and LAB_POST_PUSH_CMD
  --verify-only   run verify() only; implies all --no-* above and skips
                  pre_hook, run_scenario, and post_hook

Required environment for SSH VM scenarios:
  LAB_HV_HOST, LAB_HV_USER, LAB_VM_IP, LAB_VM_USER

Optional environment:
  LAB_RESULTS_DIR, LAB_VM_NAME, LAB_GOLDEN_CHECKPOINT
  LAB_STAGE_DIR, LAB_STAGE_SOURCES
  LAB_PUSH_FILES, LAB_REMOTE_PUSH_DIR, LAB_POST_PUSH_CMD
USAGE
}

SCENARIO_FILE=""
STAGE=1
RESET=1
PUSH=1
VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --no-stage) STAGE=0 ;;
        --no-reset) RESET=0 ;;
        --no-push) PUSH=0 ;;
        --verify-only) VERIFY_ONLY=1; STAGE=0; RESET=0; PUSH=0 ;;
        -*) echo "Unknown flag: $1" >&2; usage >&2; exit 2 ;;
        *)  [[ -n "$SCENARIO_FILE" ]] && { echo "Only one scenario may be given." >&2; exit 2; }
            SCENARIO_FILE="$1" ;;
    esac
    shift
done

[[ -n "$SCENARIO_FILE" ]] || { usage >&2; exit 2; }
[[ -f "$SCENARIO_FILE" ]] || { echo "Scenario not found: $SCENARIO_FILE" >&2; exit 2; }

ssh_host() {
    ssh "${LAB_HV_USER}@${LAB_HV_HOST}" "$@"
}

ssh_vm() {
    : "${LAB_VM_IP:?LAB_VM_IP required}"
    : "${LAB_VM_USER:?LAB_VM_USER required}"
    ssh -J "${LAB_HV_USER}@${LAB_HV_HOST}" "${LAB_VM_USER}@${LAB_VM_IP}" "$@"
}

scp_to_vm() {
    : "${LAB_VM_IP:?LAB_VM_IP required}"
    : "${LAB_VM_USER:?LAB_VM_USER required}"
    scp -J "${LAB_HV_USER}@${LAB_HV_HOST}" "$@" "${LAB_VM_USER}@${LAB_VM_IP}:${LAB_REMOTE_PUSH_DIR}/"
}

say()  { echo "--- [$(date -u +%H:%M:%S)] $*"; }
step() { echo; echo "=============================================================="
         echo "=== $*"
         echo "=============================================================="; }

run_scenario() { echo "scenario: run_scenario() not defined"; return 2; }
verify()       { echo "scenario: verify() not defined"; return 2; }
pre_hook()     { :; }
post_hook()    { :; }

# shellcheck disable=SC1090
source "$SCENARIO_FILE"

mkdir -p "$LAB_RESULTS_DIR"
scenario_name="$(basename "$SCENARIO_FILE" .sh)"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
log="$LAB_RESULTS_DIR/${scenario_name}-${ts}.log"

exec > >(tee -a "$log") 2>&1

rc=2
trap 'say "EXIT rc=$rc log=$log"' EXIT

step "lab=$LAB_NAME scenario=$scenario_name log=$log"

# 1. Stage helper scripts to the host share (if configured).
if [[ $STAGE -eq 1 && -n "$LAB_STAGE_SOURCES" ]]; then
    step "stage helper scripts -> $LAB_STAGE_DIR"
    : "${LAB_STAGE_DIR:?LAB_STAGE_DIR required when LAB_STAGE_SOURCES is set}"
    if [[ -d "$LAB_STAGE_DIR" ]]; then
        # LAB_STAGE_SOURCES is a space-separated list of globs. Unquoted on
        # purpose so the shell expands them.
        # shellcheck disable=SC2086
        for src in $LAB_STAGE_SOURCES; do
            # Each token may itself be a glob; let the shell re-expand it.
            # shellcheck disable=SC2086
            for f in $src; do
                if [[ -f "$f" ]]; then
                    cp -f "$f" "$LAB_STAGE_DIR"/ || true
                fi
            done
        done
        ls -la "$LAB_STAGE_DIR"/ | tail -20
    else
        say "WARN: $LAB_STAGE_DIR not present - skipping stage"
    fi
else
    say "skipping stage"
fi

# 2. Revert VM to its golden checkpoint.
if [[ $RESET -eq 1 ]]; then
    : "${LAB_VM_NAME:?LAB_VM_NAME required for reset}"
    step "revert $LAB_VM_NAME to $LAB_GOLDEN_CHECKPOINT"
    ssh_host "pwsh -File D:\\ISO\\lab-scripts\\Revert-TestVM.ps1 -VMName '$LAB_VM_NAME' -Checkpoint '$LAB_GOLDEN_CHECKPOINT'"

    say "wait for ${LAB_VM_IP} SSH"
    for _ in $(seq 1 60); do
        if ssh -o ConnectTimeout=3 -o BatchMode=yes \
               -J "${LAB_HV_USER}@${LAB_HV_HOST}" "${LAB_VM_USER}@${LAB_VM_IP}" true 2>/dev/null; then
            break
        fi
        sleep 2
    done
else
    say "skipping VM revert"
fi

# 3. Push current appliance files to the VM.
if [[ $PUSH -eq 1 && -n "$LAB_PUSH_FILES" ]]; then
    step "push files to appliance"
    # shellcheck disable=SC2086
    scp_to_vm $LAB_PUSH_FILES

    if [[ -n "$LAB_POST_PUSH_CMD" ]]; then
        step "post-push command"
        ssh_vm "$LAB_POST_PUSH_CMD"
    fi
else
    say "skipping file push"
fi

if [[ $VERIFY_ONLY -eq 0 ]]; then
    step "pre_hook"
    pre_hook

    step "scenario body"
    run_scenario || true
fi

step "verify"
if verify; then
    say "PASS"
    rc=0
else
    say "FAIL"
    rc=1
fi

if [[ $VERIFY_ONLY -eq 0 ]]; then
    step "post_hook"
    post_hook || true
fi

exit "$rc"
