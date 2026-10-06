#!/bin/bash
# ==============================================================================
# Quantum - Plymouth boot theme installer
# Source: plymouth/install.sh
# Status: ran on the author's workstation 2026-09-24 with --grub-bg and --quiet-boot,
#         as 'sovereign-boot', its pre-publication name.
#         UNTESTED since the rename and the driver-aware GPU checks.
#
# Installs theme/ (full-screen wallpaper + rotating activity spinner) as the
# active Plymouth theme, optionally sets a GRUB menu background, keeps the
# boot resolution through the GRUB -> kernel hand-off, and rebuilds the
# initramfs for every installed kernel.
#
# GUARDED change (bootloader + initramfs). Run --dry-run first; see
# CHANGE_RECORD.md. Run prepare-boot-graphics.sh --check before this.
#
# Usage:
#   sudo bash install.sh [options]
#
# Options:
#   --theme-name NAME   lower-case letters, digits, hyphens (default: quantum)
#   --backgrounds DIR   take background-wide.png and background-16x9.png from DIR
#                       instead of theme/ (make them with build/prepare_backgrounds.py)
#   --grub-bg PATH      PNG or JPEG to use as the GRUB menu background (optional)
#   --resolution WxH    force the GRUB mode instead of reading the connected monitor
#   --quiet-boot        add quiet loglevel=3 vt.global_cursor_default=0 to
#                       GRUB_CMDLINE_LINUX_DEFAULT (hides kernel/systemd console text
#                       around the splash; Esc and journalctl still show everything)
#   --dry-run           print current vs planned state; change nothing
#   -h, --help          this text
#
# Run as root. From a noexec mount use: sudo bash plymouth/install.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
THEME_SRC_DIR="${SCRIPT_DIR}/theme"

DRY_RUN=0
THEME_NAME="quantum"
GRUB_BG_PATH=""
BG_DIR=""
FORCED_RESOLUTION=""
QUIET_BOOT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --theme-name) THEME_NAME="$(need_arg "$@")"; shift 2 ;;
        --grub-bg)    GRUB_BG_PATH="$(need_arg "$@")"; shift 2 ;;
        --backgrounds) BG_DIR="$(need_arg "$@")"; shift 2 ;;
        --resolution) FORCED_RESOLUTION="$(need_arg "$@")"; shift 2 ;;
        --dry-run)    DRY_RUN=1; shift ;;
        --quiet-boot) QUIET_BOOT=1; shift ;;
        -h|--help)    sed -n '2,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            die "unknown argument: $1 (see --help)" ;;
    esac
done

# ---- pre-flight (read-only) ---------------------------------------------------
require_root
require_cmds update-alternatives update-grub update-initramfs lsinitramfs plymouth
require_initramfs_tools
[[ "$THEME_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "theme name must be lower-case letters, digits, hyphens: '$THEME_NAME'"

BG_DIR="${BG_DIR:-$THEME_SRC_DIR}"
for f in quantum.script quantum.plymouth.in wheel.png; do
    [[ -f "${THEME_SRC_DIR}/$f" ]] || die "missing ${THEME_SRC_DIR}/$f (see build/)"
done
is_png "${THEME_SRC_DIR}/wheel.png" || die "${THEME_SRC_DIR}/wheel.png is not a PNG"
for f in background-wide.png background-16x9.png; do
    [[ -f "${BG_DIR}/$f" ]] || die "missing ${BG_DIR}/$f (build/generate_backgrounds.py or build/prepare_backgrounds.py make it)"
    is_png "${BG_DIR}/$f" || die "${BG_DIR}/$f is not a PNG (Plymouth's script module loads PNG only)"
done

SCRIPT_PLUGIN="$(find /usr/lib -path '*/plymouth/script.so' -print -quit 2>/dev/null || true)"
[[ -n "$SCRIPT_PLUGIN" ]] || die "Plymouth 'script' plugin (script.so) not found — install the package that ships it (plymouth-themes on Ubuntu) first."

GRUB_BG_EXT=""
if [[ -n "$GRUB_BG_PATH" ]]; then
    [[ -f "$GRUB_BG_PATH" ]] || die "'$GRUB_BG_PATH' does not exist"
    if is_png "$GRUB_BG_PATH"; then GRUB_BG_EXT="png"
    elif is_jpeg "$GRUB_BG_PATH"; then GRUB_BG_EXT="jpg"
    else die "'$GRUB_BG_PATH' is neither PNG nor JPEG"; fi
fi

# Resolution: the connected connector's preferred (first-listed) DRM mode.
RES_SOURCE=""
if [[ -n "$FORCED_RESOLUTION" ]]; then
    RESOLUTION="$FORCED_RESOLUTION"; RES_SOURCE="--resolution"
else
    RESOLUTION=""
    for conn in /sys/class/drm/card*-*; do
        [[ "$(cat "$conn/status" 2>/dev/null || true)" == "connected" ]] || continue
        RESOLUTION="$(head -n1 "$conn/modes" 2>/dev/null || true)"
        [[ -n "$RESOLUTION" ]] && { RES_SOURCE="DRM $(basename "$conn") preferred mode"; break; }
    done
    [[ -n "$RESOLUTION" ]] || die "no connected monitor found under /sys/class/drm; pass --resolution WxH"
fi
[[ "$RESOLUTION" =~ ^[0-9]+x[0-9]+$ ]] || die "resolution '$RESOLUTION' is not WxH"

# Kernel command line: 'splash' is required, 'nomodeset' defeats native res.
CMDLINE_DEFAULT="$(grub_get GRUB_CMDLINE_LINUX_DEFAULT)"
[[ "$CMDLINE_DEFAULT" == *splash* ]] || warn "GRUB_CMDLINE_LINUX_DEFAULT has no 'splash' — Plymouth will not show a graphical splash. Add it before relying on this theme."
[[ "$CMDLINE_DEFAULT $(grub_get GRUB_CMDLINE_LINUX)" == *nomodeset* ]] && warn "'nomodeset' is on the kernel command line — the splash will run at a low-res fallback."

# --quiet-boot: add missing tokens, keep everything already there (an existing
# loglevel= is left alone).
NEW_CMDLINE_DEFAULT="$CMDLINE_DEFAULT"
if [[ $QUIET_BOOT -eq 1 ]]; then
    cur=""
    if [[ "$CMDLINE_DEFAULT" != "$UNSET" ]]; then cur="${CMDLINE_DEFAULT#\"}"; cur="${cur%\"}"; fi
    for tok in quiet splash loglevel=3 vt.global_cursor_default=0; do
        [[ " $cur " == *" ${tok%%=*}"[=\ ]* ]] || cur="${cur:+$cur }$tok"
    done
    NEW_CMDLINE_DEFAULT="\"${cur}\""
fi

# Early KMS: is the display's driver in the running kernel's initrd? (informational)
CUR_INITRD="/boot/initrd.img-$(uname -r)"
KMS_DRIVER="$(kms_driver)"
if [[ -z "$KMS_DRIVER" ]]; then
    KMS_STATE="no connected display found; cannot tell"
elif initrd_contains "$CUR_INITRD" "/${KMS_DRIVER}\.ko"; then
    KMS_STATE="${KMS_DRIVER} present in ${CUR_INITRD}"
else
    KMS_STATE="${KMS_DRIVER} NOT in ${CUR_INITRD} — run prepare-boot-graphics.sh first"
fi

# ---- refuse to record a rollback target that is this theme --------------------
# The first install writes original.env, and uninstall restores it. If this theme is
# already the selected one when that record is first written - installed by another
# route, or under an earlier name - the record would point at what is being installed,
# and a later uninstall would restore the theme it then deletes. The user-level theme's
# uninstaller had exactly that defect, found on a live host, so it is guarded here.
if [[ ! -f "$ORIGINAL_STATE" ]]; then
    LEGACY_STATE="/var/lib/sovereign-plymouth/original.env"
    [[ -f "$LEGACY_STATE" ]] && die "found ${LEGACY_STATE}: this theme is already installed under its pre-publication name 'sovereign-boot'. Roll that install back first with the uninstall script it came with, then run this again - otherwise 'sovereign-boot' becomes the state this package restores."
    [[ "$(plymouthd_theme_get)" == "$THEME_NAME" ]] && die "plymouthd.conf already selects '${THEME_NAME}' but ${ORIGINAL_STATE} does not exist, so the pre-install state is unknown. Select your previous theme first (sudo plymouth-set-default-theme <name>), then run this again."
fi

THEME_DIR="/usr/share/plymouth/themes/${THEME_NAME}"
THEME_FILE="${THEME_DIR}/${THEME_NAME}.plymouth"
NEW_GFXMODE="\"${RESOLUTION},auto\""

cat <<PLAN

                         current                               -> planned
plymouthd.conf Theme     $(plymouthd_theme_get)  -> ${THEME_NAME}
default.plymouth         $(alt_value) ($(alt_status))  -> ${THEME_FILE} (manual)
GRUB_GFXMODE             $(grub_get GRUB_GFXMODE)  -> ${NEW_GFXMODE}   [${RES_SOURCE}]
GRUB_GFXPAYLOAD_LINUX    $(grub_get GRUB_GFXPAYLOAD_LINUX)  -> "keep"
GRUB_CMDLINE_LINUX_DEFAULT $CMDLINE_DEFAULT  -> $([[ "$NEW_CMDLINE_DEFAULT" != "$CMDLINE_DEFAULT" ]] && echo "$NEW_CMDLINE_DEFAULT" || echo "(unchanged)")
GRUB_BACKGROUND          $(grub_get GRUB_BACKGROUND)  -> $([[ -n "$GRUB_BG_EXT" ]] && echo "\"/boot/grub/quantum-bg.${GRUB_BG_EXT}\"" || echo "(unchanged)")
theme files              -> ${THEME_DIR}/
backgrounds from         ${BG_DIR}/
initramfs                -> rebuild for all kernels: $(cd /boot && ls initrd.img-* 2>/dev/null | tr '\n' ' ')
KMS driver (early)       ${KMS_STATE}
plymouth script plugin   ${SCRIPT_PLUGIN}
state / backups          ${STATE_DIR}/

PLAN

if [[ $DRY_RUN -eq 1 ]]; then
    log "Dry run: nothing changed."
    exit 0
fi

# ---- state: original values are recorded once, by the first install ----------
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
BACKUP_DIR="$(snapshot_files "$GRUB_FILE" "$PLYMOUTHD_CONF")"
log "Snapshot of ${GRUB_FILE} and ${PLYMOUTHD_CONF} -> ${BACKUP_DIR}"

if [[ ! -f "$ORIGINAL_STATE" ]]; then
    {
        printf 'ORIG_PLYMOUTHD_THEME=%q\n'     "$(plymouthd_theme_get)"
        printf 'ORIG_ALT_VALUE=%q\n'           "$(alt_value)"
        printf 'ORIG_ALT_STATUS=%q\n'          "$(alt_status)"
        printf 'ORIG_GRUB_GFXMODE=%q\n'        "$(grub_get GRUB_GFXMODE)"
        printf 'ORIG_GRUB_GFXPAYLOAD_LINUX=%q\n' "$(grub_get GRUB_GFXPAYLOAD_LINUX)"
        printf 'ORIG_GRUB_BACKGROUND=%q\n'     "$(grub_get GRUB_BACKGROUND)"
        printf 'INSTALLED_THEME_NAME=%q\n'     "$THEME_NAME"
    } > "$ORIGINAL_STATE"
    chmod 600 "$ORIGINAL_STATE"
    log "Recorded pre-install state -> ${ORIGINAL_STATE}"
else
    log "Keeping existing ${ORIGINAL_STATE} (re-install; the pre-first-install state stays the rollback target)."
fi
# Keys added to the package after a first install: record their value now,
# before this run changes them, if they were never recorded.
if ! grep -q '^ORIG_GRUB_CMDLINE_LINUX_DEFAULT=' "$ORIGINAL_STATE"; then
    printf 'ORIG_GRUB_CMDLINE_LINUX_DEFAULT=%q\n' "$CMDLINE_DEFAULT" >> "$ORIGINAL_STATE"
fi

# ---- theme files ---------------------------------------------------------------
log "Installing theme to ${THEME_DIR}"
install -d -m 755 "$THEME_DIR"
install -m 644 "${THEME_SRC_DIR}/wheel.png" "${THEME_DIR}/wheel.png"
for f in background-wide.png background-16x9.png; do
    install -m 644 "${BG_DIR}/$f" "${THEME_DIR}/$f"
done
install -m 644 "${THEME_SRC_DIR}/quantum.script" "${THEME_DIR}/${THEME_NAME}.script"
sed -e "s|@THEME_NAME@|${THEME_NAME}|g" -e "s|@THEME_DIR@|${THEME_DIR}|g" \
    "${THEME_SRC_DIR}/quantum.plymouth.in" > "$THEME_FILE"
chmod 644 "$THEME_FILE"

# ---- select the theme (both mechanisms; plymouthd.conf wins at runtime) --------
update-alternatives --install "$ALT_LINK" default.plymouth "$THEME_FILE" 100
update-alternatives --set default.plymouth "$THEME_FILE"
plymouthd_theme_set "$THEME_NAME"
log "plymouthd.conf Theme=$(plymouthd_theme_get); default.plymouth=$(alt_value)"

# ---- GRUB ----------------------------------------------------------------------
grub_set GRUB_GFXMODE "$NEW_GFXMODE"
grub_set GRUB_GFXPAYLOAD_LINUX '"keep"'
[[ "$NEW_CMDLINE_DEFAULT" != "$CMDLINE_DEFAULT" ]] && grub_set GRUB_CMDLINE_LINUX_DEFAULT "$NEW_CMDLINE_DEFAULT"
if [[ -n "$GRUB_BG_EXT" ]]; then
    rm -f /boot/grub/quantum-bg.png /boot/grub/quantum-bg.jpg
    install -m 644 "$GRUB_BG_PATH" "/boot/grub/quantum-bg.${GRUB_BG_EXT}"
    grub_set GRUB_BACKGROUND "\"/boot/grub/quantum-bg.${GRUB_BG_EXT}\""
fi

log "update-grub"
update-grub
log "update-initramfs -u -k all"
update-initramfs -u -k all

# ---- post-checks ----------------------------------------------------------------
FAIL=0
for initrd in /boot/initrd.img-*; do
    if initrd_contains "$initrd" "themes/${THEME_NAME}/${THEME_NAME}\.script"; then
        log "OK   theme present in ${initrd}"
    else
        warn "theme NOT present in ${initrd}"; FAIL=1
    fi
done
[[ "$(plymouthd_theme_get)" == "$THEME_NAME" ]] || { warn "plymouthd.conf Theme is not ${THEME_NAME}"; FAIL=1; }

if [[ $FAIL -ne 0 ]]; then
    echo
    warn "post-install checks failed — do not reboot on this. Roll back with: sudo bash \"${SCRIPT_DIR}/uninstall.sh\""
    exit 2
fi

cat <<DONE

Installed. Next:
  1. Preview without rebooting (from a text console, Ctrl+Alt+F3):
       sudo bash "${SCRIPT_DIR}/verify.sh" --preview
  2. Reboot. Expect: GRUB menu$([[ -n "$GRUB_BG_EXT" ]] && echo " over the background image"), then the wallpaper fading in with the spinner below the glow. Press Esc mid-boot: the boot log should appear.
Roll back:
  sudo bash "${SCRIPT_DIR}/uninstall.sh"
DONE
