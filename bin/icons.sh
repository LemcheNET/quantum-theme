#!/usr/bin/env bash
# Fetch and install this variant's Slot icon theme (l4k1, GPLv3).
#
# Not bundled, and the sets differ by variant: measured on quantum 2026-10-04,
# Slot-Light-Icons is 13,435 files / 182 MiB and Slot-Dark-Icons 19,436 / 215 MiB - two
# orders of magnitude bigger than everything else here put together. It is a dependency,
# fetched on demand. Use --check for the figures on your host; upstream changes them.
#
# Usage:  icons.sh --variant light              # sparse clone, install to ~/.local/share/icons
#         icons.sh --variant light --dedupe     # hardlink identical files afterwards (prints real before/after)
#         icons.sh --variant light --from <dir> # install from a clone or download you already have
#         icons.sh --variant light --check      # report what is installed, change nothing
#
# UNTESTED. Downloads on the order of 100-200 MiB over the network.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
quantum_init "$@"; set -- "${QUANTUM_ARGS[@]+"${QUANTUM_ARGS[@]}"}"

REPO="https://github.com/L4ki/Slot-Plasma-Themes.git"
DEST="$DATA/icons/$ICON_THEME"
DEDUPE=0
FROM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dedupe) DEDUPE=1; shift ;;
    --from)   FROM="${2:?--from needs a directory}"; shift 2 ;;
    --check)
      for d in "$DEST" "$SYSDATA/icons/$ICON_THEME"; do
        if [[ -f "$d/index.theme" ]]; then
          say "installed: $d"
          printf '    %s\n' "$(grep -m1 '^Inherits=' "$d/index.theme")"
          printf '    %s files, %s\n' "$(find "$d" -type f | wc -l)" "$(du -sh "$d" | cut -f1)"
        else
          echo "    not present: $d"
        fi
      done
      exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ -z "$FROM" ]]; then
  command -v git >/dev/null || die "git not found"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  say "sparse clone (only $ICON_SUBDIR, not the 559 MiB repo)"
  if git clone --depth 1 --filter=blob:none --sparse "$REPO" "$TMP/repo" 2>/dev/null; then
    git -C "$TMP/repo" sparse-checkout set "$ICON_SUBDIR"
  else
    warn "sparse clone unavailable (git < 2.25?) - falling back to a full shallow clone"
    git clone --depth 1 "$REPO" "$TMP/repo"
  fi
  FROM="$TMP/repo/$ICON_SUBDIR"
fi

[[ -f "$FROM/index.theme" ]] || die "no index.theme under $FROM"
grep -q "^Name=$ICON_THEME" "$FROM/index.theme" || warn "index.theme Name= is not $ICON_THEME - check what you fetched"

say "installing to $DEST"
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -a "$FROM" "$DEST"

if [[ $DEDUPE -eq 1 ]]; then
  before=$(du -sm "$DEST" | cut -f1)
  if command -v rdfind >/dev/null; then
    say "hardlinking duplicates with rdfind"
    rdfind -makehardlinks true -outputname /dev/null "$DEST" >/dev/null
  elif command -v hardlink >/dev/null; then
    say "hardlinking duplicates with hardlink(1)"
    hardlink "$DEST" >/dev/null
  else
    say "hardlinking duplicates (built-in, md5 within equal sizes)"
    python3 - "$DEST" <<'PY'
import hashlib, os, sys, collections
root = sys.argv[1]
sizes = collections.defaultdict(list)
for dp, _, fs in os.walk(root):
    for f in fs:
        p = os.path.join(dp, f)
        if not os.path.islink(p):
            sizes[os.path.getsize(p)].append(p)
linked = 0
for s, ps in sizes.items():
    if len(ps) < 2 or s == 0:
        continue
    seen = {}
    for p in ps:
        h = hashlib.md5(open(p, 'rb').read()).hexdigest()
        if h in seen:
            if os.stat(p).st_ino != os.stat(seen[h]).st_ino:
                os.remove(p); os.link(seen[h], p); linked += 1
        else:
            seen[h] = p
print(f"    hardlinked {linked} files")
PY
  fi
  after=$(du -sm "$DEST" | cut -f1)
  say "size ${before} MiB -> ${after} MiB"
  warn "hardlinked: editing one icon now edits every identical copy. Re-run without --dedupe to undo."
fi

say "refreshing icon caches"
rm -f "$CACHE/icon-cache.kcache" 2>/dev/null || true
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -f "$DEST" 2>/dev/null || true

say "done: $(find "$DEST" -type f | wc -l) files, $(du -sh "$DEST" | cut -f1)"
say "the $NAME global theme already points at $ICON_THEME; apply it, or:"
echo "    kwriteconfig6 --file kdeglobals --group Icons --key Theme $ICON_THEME"
