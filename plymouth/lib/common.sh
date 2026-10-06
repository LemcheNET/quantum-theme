# shellcheck shell=bash
# ==============================================================================
# Shared helpers for the Quantum Plymouth package.
# Source: plymouth/lib/common.sh  (sourced, never executed)
# Status: used by the scripts that ran on the author's workstation 2026-09-24,
#         as 'sovereign-boot', its pre-publication name.
# ==============================================================================

# Variables below are used by the scripts that source this file.
# shellcheck disable=SC2034
{
STATE_DIR="/var/lib/quantum-plymouth"
ORIGINAL_STATE="${STATE_DIR}/original.env"   # written once, by the first install
GRUB_FILE="/etc/default/grub"
PLYMOUTHD_CONF="/etc/plymouth/plymouthd.conf"
ALT_LINK="/usr/share/plymouth/themes/default.plymouth"
UNSET="__UNSET__"
}

log()  { echo "-> $*"; }
warn() { echo "WARNING: $*" >&2; }
die()  { echo "Error: $*" >&2; exit 1; }

# Value of an option's argument, or die. Usage: v="$(need_arg "$@")"
need_arg() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 needs a value"; printf '%s' "$2"; }

require_root() { [[ $EUID -eq 0 ]] || die "must be run as root (sudo)."; }

require_cmds() {
    local missing=() c
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
    [[ ${#missing[@]} -eq 0 ]] || die "missing commands: ${missing[*]}"
}

# initramfs-tools only (Debian/Ubuntu family). Developed against initramfs-tools 0.151ubuntu1.
require_initramfs_tools() {
    command -v dracut >/dev/null 2>&1 && warn "dracut is installed. These scripts target initramfs-tools; check which one built /boot/initrd.img-*."
    [[ -d /etc/initramfs-tools ]] || die "/etc/initramfs-tools missing — this package only supports initramfs-tools."
}

# True if the initrd contains a path matching the (grep -E) pattern.
# grep -c reads all input, so lsinitramfs never gets SIGPIPE under pipefail.
initrd_contains() {
    local n
    n="$(lsinitramfs "$1" 2>/dev/null | grep -cE -- "$2" || true)"
    [[ "${n:-0}" -gt 0 ]]
}

# The kernel driver behind the first connected display: amdgpu, i915, nouveau,
# nvidia, ... Empty when no display is connected or sysfs is not laid out as expected.
# The splash gets the native mode only if this driver is in the initrd, so the checks
# look for "<driver>.ko" there rather than assuming one vendor.
kms_driver() {
    local conn card link
    for conn in /sys/class/drm/card*-*; do
        [[ "$(cat "$conn/status" 2>/dev/null || true)" == "connected" ]] || continue
        card="$(basename "$conn")"; card="${card%%-*}"          # card1-DP-1 -> card1
        link="$(readlink -f "/sys/class/drm/${card}/device/driver" 2>/dev/null || true)"
        [[ -n "$link" ]] && { echo "${link##*/}"; return 0; }
    done
    return 0
}

# A firmware framebuffer means the native KMS driver has not taken over (yet).
is_firmware_fb() { [[ "$1" == simpledrm* || "$1" == efifb* || "$1" == vesafb* || "$1" == none ]]; }

is_png()  { [[ "$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')" == "89504e470d0a1a0a" ]]; }
is_jpeg() { [[ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" == "ffd8ff" ]]; }

# --- update-alternatives: default.plymouth -----------------------------------
alt_value()  { update-alternatives --query default.plymouth 2>/dev/null | sed -n 's/^Value: //p' || true; }
alt_status() { update-alternatives --query default.plymouth 2>/dev/null | sed -n 's/^Status: //p' || true; }

# --- /etc/plymouth/plymouthd.conf: [Daemon] Theme= ----------------------------
# This file OVERRIDES the default.plymouth alternative when it sets Theme=.
plymouthd_theme_get() {
    [[ -f "$PLYMOUTHD_CONF" ]] || { echo "$UNSET"; return; }
    local v; v="$(sed -n 's/^Theme=//p' "$PLYMOUTHD_CONF" | tail -n1)"
    echo "${v:-$UNSET}"
}
plymouthd_theme_set() {
    local theme="$1"
    if [[ "$theme" == "$UNSET" ]]; then
        [[ -f "$PLYMOUTHD_CONF" ]] && sed -i '/^Theme=/d' "$PLYMOUTHD_CONF"
        return
    fi
    mkdir -p "$(dirname "$PLYMOUTHD_CONF")"
    if [[ ! -f "$PLYMOUTHD_CONF" ]]; then
        printf '[Daemon]\nTheme=%s\n' "$theme" > "$PLYMOUTHD_CONF"
    elif grep -q '^Theme=' "$PLYMOUTHD_CONF"; then
        sed -i "s|^Theme=.*|Theme=${theme}|" "$PLYMOUTHD_CONF"
    elif grep -q '^\[Daemon\]' "$PLYMOUTHD_CONF"; then
        sed -i "/^\[Daemon\]/a Theme=${theme}" "$PLYMOUTHD_CONF"
    else
        printf '\n[Daemon]\nTheme=%s\n' "$theme" >> "$PLYMOUTHD_CONF"
    fi
}

# --- /etc/default/grub: single KEY=value lines, raw value incl. quotes -------
grub_get() {
    local v; v="$(sed -n "s/^$1=//p" "$GRUB_FILE" | tail -n1)"
    echo "${v:-$UNSET}"
}
grub_set() {   # grub_set KEY RAW_VALUE   (RAW_VALUE includes quotes, or $UNSET to delete)
    local key="$1" val="$2"
    if [[ "$val" == "$UNSET" ]]; then
        sed -i "/^${key}=/d" "$GRUB_FILE"
    elif grep -q "^${key}=" "$GRUB_FILE"; then
        # '|' delimiter; values here never contain it (paths, WxH lists, "keep")
        sed -i "s|^${key}=.*|${key}=${val}|" "$GRUB_FILE"
    else
        printf '%s=%s\n' "$key" "$val" >> "$GRUB_FILE"
    fi
}

# Full copies of every file we touch, per run, for manual recovery.
snapshot_files() {
    local dir
    dir="${STATE_DIR}/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir"
    local f
    for f in "$@"; do [[ -e "$f" ]] && cp -a "$f" "$dir/"; done
    echo "$dir"
}
