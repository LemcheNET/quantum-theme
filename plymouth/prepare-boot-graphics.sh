#!/bin/bash
# ==============================================================================
# Quantum - early-KMS prerequisites for a graphical boot
# Source: plymouth/prepare-boot-graphics.sh
# Status: check mode ran on the author's workstation 2026-09-24 (all OK) when this
#         script was amdgpu-only. Made driver-aware since: UNTESTED in this form.
#         --apply and --revert have never run.
#
# Makes sure every initrd can bring up the display's KMS driver (amdgpu, i915,
# nouveau, ... whichever drives the first connected display) before Plymouth
# starts, so the splash gets the monitor's native mode instead of a firmware or
# low-res fallback. Targets initramfs-tools only (Debian/Ubuntu family).
#
# Check first. On a stock Ubuntu install the plymouth initramfs hook already
# pulls in the DRM drivers, so --apply is often a no-op. It only adds what a
# check shows is missing, and records it so --revert removes exactly that.
#
# Does NOT touch the kernel command line. If 'nomodeset' is present, or
# 'splash' is missing, it says so; editing GRUB_CMDLINE_LINUX_DEFAULT is a
# separate decision.
#
# Usage:
#   sudo bash prepare-boot-graphics.sh              # read-only check (default)
#   sudo bash prepare-boot-graphics.sh --apply [--dry-run]
#   sudo bash prepare-boot-graphics.sh --revert [--dry-run]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MODULES_FILE="/etc/initramfs-tools/modules"
CONFD_FILE="/etc/initramfs-tools/conf.d/quantum-boot-graphics"
MARKER="# quantum: early KMS for Plymouth (prepare-boot-graphics.sh)"
PREP_STATE="${STATE_DIR}/prepare-boot-graphics.env"

MODE="check"; DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)   MODE="apply"; shift ;;
        --revert)  MODE="revert"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

require_root
require_cmds lsinitramfs update-initramfs
require_initramfs_tools

KMS_DRIVER="$(kms_driver)"
[[ -n "$KMS_DRIVER" ]] || die "no connected display found under /sys/class/drm, so there is no driver to check."
[[ "$KMS_DRIVER" =~ ^[a-z0-9_-]+$ ]] || die "unexpected driver name '${KMS_DRIVER}'"

# Effective FRAMEBUFFER: last assignment across the files initramfs-tools reads.
framebuffer_setting() {
    local f v=""
    for f in /usr/share/initramfs-tools/conf-hooks.d/* /etc/initramfs-tools/initramfs.conf /etc/initramfs-tools/conf.d/*; do
        [[ -f "$f" ]] || continue
        local line; line="$(grep -E '^\s*FRAMEBUFFER=' "$f" | tail -n1 || true)"
        [[ -n "$line" ]] && v="${line#*=} (${f})"
    done
    echo "${v:-unset}"
}

# ---- check -----------------------------------------------------------------------
MISSING_KMS=0
check() {
    echo "== Kernel command line (GRUB_CMDLINE_LINUX_DEFAULT / GRUB_CMDLINE_LINUX) =="
    local cl; cl="$(grub_get GRUB_CMDLINE_LINUX_DEFAULT) $(grub_get GRUB_CMDLINE_LINUX)"
    [[ "$cl" == *splash* ]] && echo "  OK    splash" || echo "  FAIL  no 'splash' — Plymouth stays in text mode"
    [[ "$cl" == *nomodeset* ]] && echo "  FAIL  nomodeset — disables KMS; remove it by hand" || echo "  OK    no nomodeset"

    echo "== initramfs-tools configuration =="
    echo "  info  MODULES=$(sed -n 's/^MODULES=//p' /etc/initramfs-tools/initramfs.conf | tail -n1)"
    echo "  info  FRAMEBUFFER=$(framebuffer_setting)"
    echo "  info  display driver: ${KMS_DRIVER}"
    grep -qx "$KMS_DRIVER" "$MODULES_FILE" && echo "  info  ${KMS_DRIVER} listed in ${MODULES_FILE}" || echo "  info  ${KMS_DRIVER} not listed in ${MODULES_FILE}"

    echo "== initrds =="
    local initrd n
    for initrd in /boot/initrd.img-*; do
        n="$(basename "$initrd")"
        if initrd_contains "$initrd" "/${KMS_DRIVER}\.ko"; then echo "  OK    ${n}: ${KMS_DRIVER}.ko"
        else echo "  FAIL  ${n}: ${KMS_DRIVER}.ko missing"; MISSING_KMS=1; fi
        # amdgpu cannot drive a display without its firmware. Which blobs depends on
        # the GPU generation (Navi 31 needs psp_13_0_0 and dcn_3_2_0, for instance), so
        # this only checks that the initrd carries amdgpu firmware at all. Other
        # drivers either need none for basic KMS or load it later.
        if [[ "$KMS_DRIVER" == amdgpu ]]; then
            initrd_contains "$initrd" '/firmware/amdgpu/' && echo "  OK    ${n}: amdgpu firmware present" \
                || { echo "  FAIL  ${n}: no amdgpu firmware in the initrd"; MISSING_KMS=1; }
        fi
        initrd_contains "$initrd" '/plymouth/renderers/drm\.so' && echo "  OK    ${n}: plymouth drm renderer" \
            || echo "  FAIL  ${n}: plymouth drm renderer missing (is plymouth installed?)"
    done
    echo "== Running system =="
    echo "  info  fb0: $(cat /sys/class/graphics/fb0/name 2>/dev/null || echo none)"
}

check
[[ "$MODE" == "check" ]] && exit 0

# ---- apply -----------------------------------------------------------------------
if [[ "$MODE" == "apply" ]]; then
    ADD_MODULE=0; ADD_FB=0
    [[ $MISSING_KMS -eq 1 ]] && ! grep -qx "$KMS_DRIVER" "$MODULES_FILE" && ADD_MODULE=1
    [[ "$(framebuffer_setting)" =~ ^[yY] ]] || ADD_FB=1
    echo
    echo "Plan: add ${KMS_DRIVER} to ${MODULES_FILE}: $([[ $ADD_MODULE -eq 1 ]] && echo yes || echo no)"
    echo "      write ${CONFD_FILE} (FRAMEBUFFER=y): $([[ $ADD_FB -eq 1 ]] && echo yes || echo no)"
    if [[ $ADD_MODULE -eq 0 && $ADD_FB -eq 0 ]]; then
        [[ $MISSING_KMS -eq 1 ]] && warn "${KMS_DRIVER} is listed but still missing from an initrd — rebuild with 'update-initramfs -u -k all' and re-check; if it persists, inspect 'update-initramfs -v' output."
        log "Nothing to change."; exit 0
    fi
    [[ $DRY_RUN -eq 1 ]] && { log "Dry run: nothing changed."; exit 0; }

    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
    log "Snapshot -> $(snapshot_files "$MODULES_FILE" /etc/initramfs-tools/initramfs.conf)"
    if [[ $ADD_MODULE -eq 1 ]]; then
        printf '%s\n%s\n' "$MARKER" "$KMS_DRIVER" >> "$MODULES_FILE"   # comment on its own line: the modules file has no inline comments
        log "added ${KMS_DRIVER} to ${MODULES_FILE}"
    fi
    if [[ $ADD_FB -eq 1 ]]; then
        printf '%s\nFRAMEBUFFER=y\n' "$MARKER" > "$CONFD_FILE"; chmod 644 "$CONFD_FILE"
        log "wrote ${CONFD_FILE}"
    fi
    # The module NAME is recorded too: revert must remove what was added, which is no
    # longer always amdgpu.
    printf 'ADDED_MODULE=%s\nADDED_MODULE_NAME=%s\nADDED_CONFD=%s\n' "$ADD_MODULE" "$KMS_DRIVER" "$ADD_FB" > "$PREP_STATE"; chmod 600 "$PREP_STATE"

    log "update-initramfs -u -k all"
    update-initramfs -u -k all
    echo; echo "== Re-check =="; MISSING_KMS=0; check
    [[ $MISSING_KMS -eq 0 ]] || { warn "still missing after rebuild — do not reboot on this; run --revert and investigate."; exit 2; }
    exit 0
fi

# ---- revert ----------------------------------------------------------------------
[[ -f "$PREP_STATE" ]] || die "no ${PREP_STATE}: this script has not changed anything to revert."
ADDED_MODULE=0; ADDED_MODULE_NAME=""; ADDED_CONFD=0
# shellcheck disable=SC1090
source "$PREP_STATE"
echo
# State written before the driver-aware version recorded no name; amdgpu was the only one.
ADDED_MODULE_NAME="${ADDED_MODULE_NAME:-amdgpu}"
[[ "$ADDED_MODULE_NAME" =~ ^[a-z0-9_-]+$ ]] || die "bad ADDED_MODULE_NAME in ${PREP_STATE}"
echo "Plan: remove marked ${ADDED_MODULE_NAME} line from ${MODULES_FILE}: $([[ $ADDED_MODULE -eq 1 ]] && echo yes || echo no)"
echo "      remove ${CONFD_FILE}: $([[ $ADDED_CONFD -eq 1 ]] && echo yes || echo no)"
[[ $DRY_RUN -eq 1 ]] && { log "Dry run: nothing changed."; exit 0; }

log "Snapshot -> $(snapshot_files "$MODULES_FILE" "$CONFD_FILE")"
if [[ $ADDED_MODULE -eq 1 ]]; then
    # delete the marker line and the module line directly after it
    sed -i "/^$(printf '%s' "$MARKER" | sed 's/[][\/.*^$]/\\&/g')\$/{N;/\n${ADDED_MODULE_NAME}\$/d}" "$MODULES_FILE"
fi
[[ $ADDED_CONFD -eq 1 ]] && rm -f "$CONFD_FILE"
mv "$PREP_STATE" "${PREP_STATE}.reverted-$(date +%Y%m%d-%H%M%S)"
log "update-initramfs -u -k all"
update-initramfs -u -k all
log "Reverted."
