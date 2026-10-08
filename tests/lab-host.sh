#!/usr/bin/env bash
# lib/lab-host.sh: workstation detection, ISO share path, checksums, and the
# NoCloud seed ISO builder used by every appliance's lab staging script.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../lib/lab-host.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() {
    if [[ "$2" == "$3" ]]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); printf 'FAIL  %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}

check "forced WSL host" wsl "$(LAB_HOST_OS=wsl lab_host_os)"
check "WSL2 sees D:\\ISO at /mnt/d/ISO" /mnt/d/ISO "$(LAB_HOST_OS=wsl lab_iso_dir)"
check "macOS keeps /Volumes/ISO" /Volumes/ISO "$(LAB_HOST_OS=macos lab_iso_dir)"
check "LAB_ISO_DIR wins" /srv/iso "$(LAB_HOST_OS=wsl LAB_ISO_DIR=/srv/iso lab_iso_dir)"
check "WSL_DISTRO_NAME means WSL" wsl "$(LAB_HOST_OS='' WSL_DISTRO_NAME=Debian lab_host_os)"

printf 'abc' > "$T/f"
check "sha256 of a file" ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad "$(lab_sha256_of "$T/f")"
check "sha256 line format" "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  f" \
    "$(cd "$T" && lab_sha256 f)"

if command -v xorriso >/dev/null 2>&1 || command -v genisoimage >/dev/null 2>&1 \
    || command -v mkisofs >/dev/null 2>&1; then
    mkdir -p "$T/seed"
    printf '#cloud-config\nhostname: x\n' > "$T/seed/user-data"
    printf 'instance-id: x\n' > "$T/seed/meta-data"
    printf 'version: 2\n' > "$T/seed/network-config"
    echo stale > "$T/seed.iso"
    LAB_HOST_OS=wsl lab_make_seed_iso "$T/seed.iso" "$T/seed"
    check "seed ISO written over a stale file" yes "$([[ -s "$T/seed.iso" ]] && ! grep -qx stale "$T/seed.iso" && echo yes || echo no)"
    if command -v blkid >/dev/null 2>&1; then
        check "seed ISO volume label is CIDATA (cloud-init NoCloud)" CIDATA \
            "$(blkid -o value -s LABEL "$T/seed.iso" 2>/dev/null)"
    fi
    if command -v xorriso >/dev/null 2>&1; then
        names=$(xorriso -indev "$T/seed.iso" -find / -type f 2>/dev/null | tr -d "'" | sort | tr '\n' ' ')
        check "seed ISO keeps the lowercase cloud-init file names" \
            "/meta-data /network-config /user-data " "$names"
    fi
else
    echo "  (seed ISO checks skipped: no xorriso/genisoimage/mkisofs)"
fi
LAB_HOST_OS=wsl lab_make_seed_iso "$T/x.iso" "$T/missing" 2>/dev/null && r=made || r=refused
check "a missing seed directory is refused" refused "$r"

echo "summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
