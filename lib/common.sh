#!/usr/bin/env bash
# Shared by every script in bin/. Sourced, never executed.
#
# One copy of the logic, one set of variant facts. Everything that used to differ
# between the two forked packages now lives in variants/<slug>/variant.env, and
# everything that did not is here or in bin/.
#
# Variant selection, in order:
#   1. --variant <slug>  (or -v <slug>) on the command line; removed from the args
#   2. $QUANTUM_VARIANT
#   3. the path the script was invoked through, when that is one of the per-variant
#      symlinks: variants/dark/install.sh -> ../../bin/install.sh resolves to "dark"
#   4. error, listing what is available
#
# Callers do:
#   . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
#   quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

# ---- paths -------------------------------------------------------------------
QUANTUM_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

# ---- output ------------------------------------------------------------------
say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
ok()   { printf '  \033[1;32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; }
note() { printf '  \033[1;33m?\033[0m     %s\n' "$*"; }
die()  { warn "$*"; exit 1; }

# ---- variants ----------------------------------------------------------------
# Every slug that has a variant.env, in directory order.
quantum_variants() {
  local d
  for d in "$QUANTUM_ROOT"/variants/*/variant.env; do
    [[ -f "$d" ]] || continue
    basename "$(dirname "$d")"
  done
}

quantum_is_variant() {
  local want="$1" s
  while read -r s; do [[ "$s" == "$want" ]] && return 0; done < <(quantum_variants)
  return 1
}

# Read one key out of another variant's variant.env without disturbing ours.
# Usage: quantum_variant_get <slug> <KEY>
quantum_variant_get() {
  local slug="$1" key="$2" f="$QUANTUM_ROOT/variants/$1/variant.env"
  [[ -f "$f" ]] || return 1
  ( set -a; . "$f"; printf '%s\n' "${!key:-}" )
}

# Paths to a given variant's packages, so a script can reach across variants
# (buttons.sh does) without hardcoding either one.
quantum_vdir()        { printf '%s\n' "$QUANTUM_ROOT/variants/$1"; }
quantum_src_aurorae() { printf '%s\n' "$QUANTUM_ROOT/variants/$1/aurorae/$(quantum_variant_get "$1" ID)"; }

QUANTUM_REQUIRED_KEYS=(SLUG ID NAME BASE_SCHEME ICON_THEME ICON_SUBDIR CURSOR_THEME PORTAL_PREF GTK_PREFER_DARK)

quantum_init() {
  QUANTUM_ARGS=()
  local want="${QUANTUM_VARIANT:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --variant|-v) want="${2:?--variant needs a slug: $(quantum_variants | tr '\n' ' ')}"; shift 2 ;;
      --variant=*)  want="${1#--variant=}"; shift ;;
      *)            QUANTUM_ARGS+=("$1"); shift ;;
    esac
  done

  # 3. the symlink the script was invoked through
  if [[ -z "$want" ]]; then
    local invoked_dir
    invoked_dir="$(cd "$(dirname "$0")" && pwd)"
    local candidate; candidate="$(basename "$invoked_dir")"
    quantum_is_variant "$candidate" && want="$candidate"
  fi

  # buttons.sh works across every variant at once and only needs a "self" for --sync,
  # so it sets QUANTUM_VARIANT_OPTIONAL and copes with SLUG being empty.
  if [[ -z "$want" && "${QUANTUM_VARIANT_OPTIONAL:-0}" == 1 ]]; then
    SLUG=""; QUANTUM_VERSION="$(cat "$QUANTUM_ROOT/VERSION" 2>/dev/null || echo unknown)"
    return 0
  fi
  [[ -n "$want" ]] || die "which variant? pass --variant <$(quantum_variants | paste -sd'|' -)>, set QUANTUM_VARIANT, or run variants/<slug>/$(basename "$0")"
  quantum_is_variant "$want" || die "no such variant '$want'. Available: $(quantum_variants | tr '\n' ' ')"

  # shellcheck disable=SC1090
  set -a; . "$QUANTUM_ROOT/variants/$want/variant.env"; set +a

  local k
  for k in "${QUANTUM_REQUIRED_KEYS[@]}"; do
    [[ -n "${!k:-}" ]] || die "variants/$want/variant.env does not define $k"
  done
  [[ "$SLUG" == "$want" ]] || die "variants/$want/variant.env says SLUG=$SLUG"

  # ---- derived, so no script computes these twice --------------------------
  VDIR="$QUANTUM_ROOT/variants/$SLUG"
  AURORAE_SRC="$VDIR/aurorae/$ID"
  STYLE_SRC="$VDIR/plasma/desktoptheme/$ID"
  LNF_SRC="$VDIR/look-and-feel/$ID"
  GTK_BUNDLE="$VDIR/gtk/$ID-gtk.tar.gz"

  AURORAE_DEST="$DATA/aurorae/themes/$ID"
  STYLE_DEST="$DATA/plasma/desktoptheme/$ID"
  LNF_DEST="$DATA/plasma/look-and-feel/$ID"
  GTK_DEST="$DATA/themes/$ID"
  SCHEME_DEST="$DATA/color-schemes/$ID.colors"
  BASE_SCHEME_FILE="/usr/share/color-schemes/$BASE_SCHEME.colors"
  STATE="${XDG_STATE_HOME:-$HOME/.local/state}/quantum-$SLUG"

  QUANTUM_VERSION="$(cat "$QUANTUM_ROOT/VERSION" 2>/dev/null || echo unknown)"
}
