#!/usr/bin/env bash
# bin/lab-vm without a hypervisor: usage, argument checks, and the seed ISO.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LV="$HERE/../bin/lab-vm"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() {
    if [[ "$2" == "$3" ]]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); printf 'FAIL  %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}

check "usage lists build-base" yes "$("$LV" --help | grep -q '^  lab-vm build-base' && echo yes || echo no)"
check "unknown command fails" 1 "$("$LV" frobnicate >/dev/null 2>&1; echo $?)"
check "new without a base fails" yes \
    "$(LAB_BASE='' LAB_VM_ROOT=x LAB_SWITCH=x "$LV" new t1 2>&1 | grep -q 'no base' && echo yes || echo no)"
check "new without LAB_VM_ROOT fails" yes \
    "$(env -u LAB_VM_ROOT LAB_SWITCH=x "$LV" new t1 -b x.vhdx 2>&1 | grep -q 'LAB_VM_ROOT is not set' && echo yes || echo no)"
check "bad LAB_HYPERV fails" yes \
    "$(LAB_HYPERV=vmware "$LV" publish a b 2>&1 | grep -q 'must be local or ssh' && echo yes || echo no)"

if command -v xorriso >/dev/null 2>&1; then
    printf 'ssh-ed25519 AAAATEST user@test\n' > "$T/k.pub"
    iso=$(LAB_SEED_DIR="$T/seeds" LAB_PUBKEY="$T/k.pub" LAB_VM_USER=tester LAB_DOMAIN=example.test \
        "$LV" seed vm-a --packages "curl jq" --upgrade)
    check "seed path" "$T/seeds/vm-a-seed.iso" "$iso"
    xorriso -osirrox on -indev "$iso" -extract / "$T/x" >/dev/null 2>&1
    ud="$T/x/user-data"
    check "seed: hostname" "hostname: vm-a" "$(grep '^hostname:' "$ud")"
    check "seed: fqdn" "fqdn: vm-a.example.test" "$(grep '^fqdn:' "$ud")"
    check "seed: user" "  - name: tester" "$(grep -- '- name:' "$ud")"
    check "seed: key" "      - ssh-ed25519 AAAATEST user@test" "$(grep -- 'ssh-ed25519' "$ud")"
    check "seed: packages" 2 "$(grep -cE '^  - (curl|jq)$' "$ud")"
    check "seed: upgrade" "package_upgrade: true" "$(grep '^package_upgrade:' "$ud")"
    check "seed: instance-id per VM" yes "$(grep -q '^instance-id: vm-a-[0-9]' "$T/x/meta-data" && echo yes || echo no)"
    check "seed: network matches e*" yes "$(grep -q 'name: "e\*"' "$T/x/network-config" && echo yes || echo no)"
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
        check "seed: user-data is YAML" ok "$(python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1])); print("ok")' "$ud" 2>&1)"
        check "seed: network-config is YAML" ok "$(python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1])); print("ok")' "$T/x/network-config" 2>&1)"
    fi
    iso2=$(LAB_SEED_DIR="$T/seeds" LAB_PUBKEY="$T/k.pub" "$LV" seed vm-b)
    xorriso -osirrox on -indev "$iso2" -extract / "$T/y" >/dev/null 2>&1
    check "seed: no packages section by default" no "$(grep -q '^packages:' "$T/y/user-data" && echo yes || echo no)"
fi

printf 'lab-vm: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
