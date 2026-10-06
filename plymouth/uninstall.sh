#!/bin/bash
# ==============================================================================
# Quantum - Plymouth boot theme rollback
# Source: plymouth/uninstall.sh
# Status: UNTESTED. A real rollback has never been run, only --dry-run.
#
# Puts back exactly what the FIRST install found (recorded in
# /var/lib/quantum-plymouth/original.env): plymouthd.conf Theme=, the
# default.plymouth alternative and its auto/manual mode, and the three GRUB
# keys the installer sets. Other GRUB edits made since install are kept —
# only those keys are reverted. Removes the theme directory and GRUB
# background, then rebuilds GRUB and every initramfs.
#
# Usage:
#   sudo bash uninstall.sh [--dry-run]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

require_root
require_cmds update-alternatives update-grub update-initramfs
[[ -f "$ORIGINAL_STATE" ]] || die "no ${ORIGINAL_STATE} — nothing recorded to restore. Manual recovery: the snapshots in ${STATE_DIR}/backups/."

ORIG_PLYMOUTHD_THEME="" ORIG_ALT_VALUE="" ORIG_ALT_STATUS=""
ORIG_GRUB_GFXMODE="" ORIG_GRUB_GFXPAYLOAD_LINUX="" ORIG_GRUB_BACKGROUND="" INSTALLED_THEME_NAME=""
ORIG_GRUB_CMDLINE_LINUX_DEFAULT=""   # absent in states recorded before --quiet-boot existed
# shellcheck disable=SC1090
source "$ORIGINAL_STATE"
[[ "$INSTALLED_THEME_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "bad INSTALLED_THEME_NAME in ${ORIGINAL_STATE}"

THEME_DIR="/usr/share/plymouth/themes/${INSTALLED_THEME_NAME}"
THEME_FILE="${THEME_DIR}/${INSTALLED_THEME_NAME}.plymouth"

cat <<PLAN

                         current  -> restored
plymouthd.conf Theme     $(plymouthd_theme_get)  -> ${ORIG_PLYMOUTHD_THEME}
default.plymouth         $(alt_value)  -> ${ORIG_ALT_VALUE:-<none>} (${ORIG_ALT_STATUS:-auto})
GRUB_GFXMODE             $(grub_get GRUB_GFXMODE)  -> ${ORIG_GRUB_GFXMODE}
GRUB_GFXPAYLOAD_LINUX    $(grub_get GRUB_GFXPAYLOAD_LINUX)  -> ${ORIG_GRUB_GFXPAYLOAD_LINUX}
GRUB_BACKGROUND          $(grub_get GRUB_BACKGROUND)  -> ${ORIG_GRUB_BACKGROUND}
GRUB_CMDLINE_LINUX_DEFAULT $(grub_get GRUB_CMDLINE_LINUX_DEFAULT)  -> ${ORIG_GRUB_CMDLINE_LINUX_DEFAULT:-(unchanged, not recorded)}
remove                   ${THEME_DIR}/, /boot/grub/quantum-bg.*
rebuild                  update-grub, update-initramfs -u -k all

PLAN

if [[ $DRY_RUN -eq 1 ]]; then log "Dry run: nothing changed."; exit 0; fi

BACKUP_DIR="$(snapshot_files "$GRUB_FILE" "$PLYMOUTHD_CONF")"
log "Snapshot before rollback -> ${BACKUP_DIR}"

# Selection first, so nothing ever points at a removed theme.
plymouthd_theme_set "$ORIG_PLYMOUTHD_THEME"
if update-alternatives --list default.plymouth 2>/dev/null | grep -qxF "$THEME_FILE"; then
    update-alternatives --remove default.plymouth "$THEME_FILE"
fi
if [[ "$ORIG_ALT_STATUS" == "manual" && -f "$ORIG_ALT_VALUE" ]]; then
    update-alternatives --set default.plymouth "$ORIG_ALT_VALUE"
elif update-alternatives --query default.plymouth >/dev/null 2>&1; then
    update-alternatives --auto default.plymouth
fi
[[ "$ORIG_ALT_STATUS" == "manual" && -n "$ORIG_ALT_VALUE" && ! -f "$ORIG_ALT_VALUE" ]] && \
    warn "original alternative ${ORIG_ALT_VALUE} no longer exists; left default.plymouth in auto mode"

grub_set GRUB_GFXMODE "$ORIG_GRUB_GFXMODE"
grub_set GRUB_GFXPAYLOAD_LINUX "$ORIG_GRUB_GFXPAYLOAD_LINUX"
grub_set GRUB_BACKGROUND "$ORIG_GRUB_BACKGROUND"
[[ -n "$ORIG_GRUB_CMDLINE_LINUX_DEFAULT" ]] && grub_set GRUB_CMDLINE_LINUX_DEFAULT "$ORIG_GRUB_CMDLINE_LINUX_DEFAULT"

rm -rf -- "$THEME_DIR"
rm -f /boot/grub/quantum-bg.png /boot/grub/quantum-bg.jpg

log "update-grub"
update-grub
log "update-initramfs -u -k all"
update-initramfs -u -k all

# Rollback done: retire the record so a future install captures fresh state.
mv "$ORIGINAL_STATE" "${ORIGINAL_STATE}.restored-$(date +%Y%m%d-%H%M%S)"
log "Restored. plymouthd.conf Theme=$(plymouthd_theme_get); default.plymouth=$(alt_value). Reboot to confirm."
