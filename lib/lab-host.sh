# shellcheck shell=bash
# lab-kit lab-host.sh — workstation portability for the lab pipeline.
#
# The lab scripts run on the operator's workstation and stage files on the
# Hyper-V host's ISO share (D:\ISO on the host). Supported workstations:
#
#   wsl     WSL2 on Windows 11 (the recommended shell; dev-commons
#           SUPPORTED-ENVIRONMENTS.md). D:\ISO is /mnt/d/ISO when WSL2 runs
#           on the Hyper-V host itself; set LAB_ISO_DIR for a mapped share.
#   macos   the original Mac workflow (/Volumes/ISO, hdiutil).
#   linux   any other Linux shell (set LAB_ISO_DIR).
#
# Public surface:
#   lab_host_os                 print wsl | macos | linux
#   lab_iso_dir                 print the workstation path of the ISO share
#   lab_sha256 FILE...          "HASH  FILE" lines (sha256sum or shasum -a 256)
#   lab_sha256_of FILE          print only the hash
#   lab_make_seed_iso OUT DIR   NoCloud seed ISO (volume label CIDATA) from DIR
#   lab_strip_xattrs PATH       drop macOS extended attributes (no-op elsewhere)
#   lab_tar_create ARGS...      tar without macOS resource forks/xattrs
#   lab_need_tool TOOL [APT_PKG [BREW_PKG]]  die with an install hint if missing
#
# Overrides: LAB_HOST_OS (force detection), LAB_ISO_DIR.

[[ -n "${_LAB_HOST_LOADED:-}" ]] && return 0
_LAB_HOST_LOADED=1

lab_host_os() {
    if [[ -n "${LAB_HOST_OS:-}" ]]; then
        printf '%s\n' "$LAB_HOST_OS"
    elif [[ "$(uname -s)" == Darwin ]]; then
        echo macos
    elif [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo wsl
    else
        echo linux
    fi
}

lab_iso_dir() {
    if [[ -n "${LAB_ISO_DIR:-}" ]]; then
        printf '%s\n' "$LAB_ISO_DIR"
        return
    fi
    case "$(lab_host_os)" in
        macos) echo /Volumes/ISO ;;
        wsl)   echo /mnt/d/ISO ;;
        *)     echo /mnt/iso ;;
    esac
}

lab_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

lab_sha256_of() { lab_sha256 "$1" | awk '{ print $1 }'; }

lab_need_tool() {
    local tool="$1" apt_pkg="${2:-$1}" brew_pkg="${3:-${2:-$1}}"
    command -v "$tool" >/dev/null 2>&1 && return 0
    case "$(lab_host_os)" in
        macos) echo "error: $tool not on PATH (brew install $brew_pkg)" >&2 ;;
        *)     echo "error: $tool not on PATH (sudo apt-get install $apt_pkg)" >&2 ;;
    esac
    exit 1
}

# Build a cloud-init NoCloud seed ISO. cloud-init finds it by the volume
# label CIDATA; Joliet and Rock Ridge keep the lowercase file names
# (user-data, meta-data, network-config) intact on every reader.
lab_make_seed_iso() {
    local out="$1" dir="$2"
    [[ -d "$dir" ]] || { echo "error: seed directory missing: $dir" >&2; return 1; }
    rm -f "$out"
    if [[ "$(lab_host_os)" == macos ]] && command -v hdiutil >/dev/null 2>&1; then
        hdiutil makehybrid -iso -joliet -default-volume-name CIDATA -o "$out" "$dir" >/dev/null
    elif command -v xorriso >/dev/null 2>&1; then
        # xorriso prints a banner even with -quiet; show its output only on failure.
        local log
        log=$(xorriso -as mkisofs -quiet -volid CIDATA -joliet -rock -output "$out" "$dir" 2>&1) \
            || { printf '%s\n' "$log" >&2; return 1; }
    elif command -v genisoimage >/dev/null 2>&1; then
        genisoimage -quiet -volid CIDATA -joliet -rock -output "$out" "$dir"
    elif command -v mkisofs >/dev/null 2>&1; then
        mkisofs -quiet -volid CIDATA -joliet -rock -output "$out" "$dir"
    else
        case "$(lab_host_os)" in
            macos) echo "error: no ISO builder (hdiutil is built in; or brew install xorriso)" >&2 ;;
            *)     echo "error: no ISO builder (sudo apt-get install xorriso)" >&2 ;;
        esac
        return 1
    fi
}

lab_strip_xattrs() {
    if [[ "$(lab_host_os)" == macos ]] && command -v xattr >/dev/null 2>&1; then
        xattr -cr "$1"
    fi
    return 0
}

lab_tar_create() {
    if [[ "$(lab_host_os)" == macos ]]; then
        COPYFILE_DISABLE=1 tar --no-xattrs "$@"
    else
        tar "$@"
    fi
}
