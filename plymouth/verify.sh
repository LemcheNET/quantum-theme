#!/bin/bash
# ==============================================================================
# Quantum - Plymouth boot theme verification
# Source: plymouth/verify.sh
# Status: ran on the author's workstation 2026-09-24 (checks and --preview),
#         as 'sovereign-boot', its pre-publication name.
#         UNTESTED since the GPU checks became driver-aware.
#
# Default: read-only checks. Reading initrds needs root, so run with sudo.
# --preview renders the installed theme for N seconds without rebooting.
#   Run it from a TEXT console (Ctrl+Alt+F3, log in) — while the Plasma
#   session holds the display, plymouthd cannot draw. Press Esc during the
#   preview to check the details view. Switch back with Ctrl+Alt+F1/F2.
#
# Usage:
#   sudo bash verify.sh [--theme-name NAME]
#   sudo bash verify.sh --preview [--seconds 15]
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PREVIEW=0
SECONDS_TO_SHOW=15
THEME_NAME="quantum"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --preview)    PREVIEW=1; shift ;;
        --seconds)    SECONDS_TO_SHOW="$(need_arg "$@")"; shift 2 ;;
        --theme-name) THEME_NAME="$(need_arg "$@")"; shift 2 ;;
        -h|--help)    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            die "unknown argument: $1" ;;
    esac
done
[[ "$SECONDS_TO_SHOW" =~ ^[0-9]+$ ]] || die "--seconds must be a number"

ISSUES=0
ok()  { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; ISSUES=$((ISSUES + 1)); }
inf() { printf '  info  %s\n' "$*"; }

echo "== Selection =="
CONF_THEME="$(plymouthd_theme_get)"
[[ "$CONF_THEME" == "$THEME_NAME" ]] && ok "plymouthd.conf Theme=${CONF_THEME}" \
    || bad "plymouthd.conf Theme=${CONF_THEME} (this overrides the alternative; expected ${THEME_NAME})"
ALT="$(alt_value)"
[[ "$ALT" == */${THEME_NAME}.plymouth ]] && ok "default.plymouth -> ${ALT}" \
    || inf "default.plymouth -> ${ALT:-<none>} (secondary; plymouthd.conf wins)"

echo "== Kernel command line =="
CMDLINE="$(cat /proc/cmdline)"
[[ " $CMDLINE " == *" splash "* ]] && ok "'splash' present (running kernel)" || bad "'splash' missing from /proc/cmdline"
[[ " $CMDLINE " == *" nomodeset "* ]] && bad "'nomodeset' present — forces low-res" || ok "no 'nomodeset'"

echo "== GRUB =="
for k in GRUB_GFXMODE GRUB_GFXPAYLOAD_LINUX GRUB_BACKGROUND GRUB_THEME GRUB_TIMEOUT_STYLE; do
    inf "$(printf '%-22s %s' "$k" "$(grub_get "$k")")"
done
[[ "$(grub_get GRUB_THEME)" != "$UNSET" && "$(grub_get GRUB_BACKGROUND)" != "$UNSET" ]] && \
    bad "GRUB_THEME is set, so GRUB_BACKGROUND is ignored"

echo "== Display =="
for conn in /sys/class/drm/card*-*; do
    [[ "$(cat "$conn/status" 2>/dev/null)" == "connected" ]] || continue
    inf "$(basename "$conn"): preferred $(head -n1 "$conn/modes" 2>/dev/null)"
done
NCONN="$(grep -lx connected /sys/class/drm/card*-*/status 2>/dev/null | wc -l)"
[[ "$NCONN" -gt 1 ]] && inf "${NCONN} connected displays: the theme lays out for the first one; check the others in --preview"
# Vendor-neutral: any <driver>drmfb means a native KMS driver owns the display;
# simpledrm/efifb/vesafb mean the firmware framebuffer is still in charge.
FB="$(cat /sys/class/graphics/fb0/name 2>/dev/null || echo none)"
KMS_DRIVER="$(kms_driver)"
inf "display driver: ${KMS_DRIVER:-<none found>}"
if is_firmware_fb "$FB"; then
    bad "fb0 = ${FB}: firmware framebuffer, the native KMS driver has not taken over"
elif [[ "$FB" == *drmfb ]]; then
    ok "fb0 = ${FB}"
else
    inf "fb0 = ${FB}"
fi

echo "== initramfs (all kernels) =="
if [[ $EUID -ne 0 ]]; then
    inf "not root: skipping initrd inspection"
else
    for initrd in /boot/initrd.img-*; do
        n="$(basename "$initrd")"
        if [[ -n "$KMS_DRIVER" ]]; then
            initrd_contains "$initrd" "/${KMS_DRIVER}\.ko" && ok "${n}: ${KMS_DRIVER}" \
                || bad "${n}: ${KMS_DRIVER} missing - the splash will fall back to low resolution (run prepare-boot-graphics.sh)"
        else
            inf "${n}: no connected display, KMS driver not checked"
        fi
        initrd_contains "$initrd" "themes/${THEME_NAME}/${THEME_NAME}\.script" && ok "${n}: theme ${THEME_NAME}" || bad "${n}: theme ${THEME_NAME} missing"
        initrd_contains "$initrd" '/plymouth/script\.so' && ok "${n}: script plugin" || bad "${n}: script plugin missing"
    done
fi

echo "== Last boot =="
if command -v journalctl >/dev/null 2>&1; then
    # grep reads everything (no -m/head), so journalctl never gets SIGPIPE.
    BOOTLOG="$(journalctl -b -o short-monotonic --no-pager 2>/dev/null \
        | grep -iE 'plymouth[a-z-]*\.service|plymouthd|amdgpudrmfb|fb0: .*frame buffer' | grep -v ' sudo\[' || true)"
    if [[ -n "$BOOTLOG" ]]; then
        printf '%s\n' "$BOOTLOG" | sed -n '1,8s/^/  log   /p'
    else
        inf "no matching boot-log lines"
    fi
fi

echo
echo "Issues: ${ISSUES}"

[[ $PREVIEW -eq 1 ]] || exit $(( ISSUES > 0 ))

echo
echo "== Preview (${SECONDS_TO_SHOW}s) =="
require_root
require_cmds plymouthd plymouth
pgrep -x plymouthd >/dev/null && die "plymouthd is already running; not starting a second one"

# sudo runs the command on its own pseudo-terminal (Defaults use_pty), so
# tty(1) says /dev/pts/N even when invoked from tty3. Use the foreground VT.
ACTIVE_VT="$(cat /sys/class/tty/tty0/active 2>/dev/null || true)"
[[ "$ACTIVE_VT" =~ ^tty[0-9]+$ ]] || die "cannot determine the active virtual terminal"
VTNR="${ACTIVE_VT#tty}"
# Refuse if a graphical session owns that VT: plymouthd would fight it for the display.
if command -v loginctl >/dev/null 2>&1; then
    while read -r sid _; do
        [[ -n "$sid" ]] || continue
        stype="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
        svt="$(loginctl show-session "$sid" -p VTNr --value 2>/dev/null || true)"
        if [[ "$svt" == "$VTNR" && ( "$stype" == wayland || "$stype" == x11 ) ]]; then
            die "${ACTIVE_VT} belongs to a ${stype} session; switch to a text console (Ctrl+Alt+F3) and run it there"
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
fi
log "Rendering on /dev/${ACTIVE_VT} and every connected display"

# --tty: the VT we are looking at (plymouthd defaults to /dev/tty1).
# --debug-file: documented upstream, not yet confirmed on this build; if rejected,
# drop the option and read the debug output from the console instead.
plymouthd --debug --debug-file=/var/log/plymouth-preview.log --tty="/dev/${ACTIVE_VT}"
plymouth --show-splash
sleep "$SECONDS_TO_SHOW"
plymouth quit
echo "Preview done. Debug log: /var/log/plymouth-preview.log (look for 'script' errors)."
