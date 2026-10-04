#!/usr/bin/env bash
# Build the release artifacts for one version.
#
#   packaging/make-release.sh            build into dist/
#   packaging/make-release.sh --list     print the KDE Store product map, build nothing
#
# Two audiences, two kinds of artifact:
#
#   * dist/quantum-theme-<ver>.tar.gz   the whole repo. This is the real install path:
#                                       unpack, run bin/install.sh --variant <slug>.
#                                       Linked from each store product page.
#   * dist/<ID>-<kind>-<ver>.tar.gz     one KDE Store upload each. Store products are
#                                       per ARTIFACT TYPE, not per variant, so a Global
#                                       Theme product carries one file per variant and
#                                       the decoration and the Plasma style get products
#                                       of their own.
#
# What a store one-click install does NOT do: resolve dependencies. Installing the
# Global Theme alone gives the user a look-and-feel pointing at an Aurorae decoration,
# a Plasma style and an icon theme they do not have. Say so on the product page.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$ROOT"
VER="$(cat VERSION)"
DIST="$ROOT/dist"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# kind -> path under variants/<slug>, used for both the tarball and the store map
kinds() {
  cat <<'MAP'
aurorae      aurorae                Plasma 6 Window Decorations
plasmastyle  plasma/desktoptheme    Plasma 6 Themes
lookandfeel  look-and-feel          Global Themes (Plasma 6)
MAP
}

if [[ "${1:-}" == "--list" ]]; then
  printf '%-14s %-28s %s\n' KIND 'STORE CATEGORY' 'FILES PER PRODUCT'
  while read -r kind _ category; do
    files=""
    for env in variants/*/variant.env; do
      id=$(grep -m1 '^ID=' "$env" | cut -d= -f2)
      files+="$id-$kind-$VER.tar.gz "
    done
    printf '%-14s %-28s %s\n' "$kind" "$category" "$files"
  done < <(kinds)
  exit 0
fi

# ---- gates -------------------------------------------------------------------
say "pre-release checks"
./tests/run-tests.sh || die "tests failed - not building a release"

command -v git >/dev/null && [[ -d .git ]] && {
  [[ -z "$(git status --porcelain)" ]] || say "note: working tree is dirty; the source tarball is built from disk, not from HEAD"
}

# ---- build -------------------------------------------------------------------
rm -rf "$DIST"; mkdir -p "$DIST"

# Reproducible: fixed mtime, sorted names, no uid/gid. Two builds of one tag match.
TARFLAGS=(--sort=name --owner=0 --group=0 --numeric-owner
          --mtime="@$(git log -1 --format=%ct 2>/dev/null || echo 0)"
          --exclude-vcs --exclude='.whichbg-active' --exclude='*.kcache')

for env in variants/*/variant.env; do
  slug="$(basename "$(dirname "$env")")"
  id=$(grep -m1 '^ID=' "$env" | cut -d= -f2)
  while read -r kind subdir _; do
    src="variants/$slug/$subdir/$id"
    [[ -d "$src" ]] || die "missing $src"
    out="$DIST/$id-$kind-$VER.tar.gz"
    # The archive's single top-level directory must be the package id: that is what
    # KNewStuff and the KCMs unpack straight into ~/.local/share/<...>/.
    tar czf "$out" "${TARFLAGS[@]}" -C "variants/$slug/$subdir" "$id"
    say "$(basename "$out") ($(du -h "$out" | cut -f1))"
  done < <(kinds)
  # the prebuilt GTK theme, for anyone who wants it without the repo
  gtk="variants/$slug/gtk/$id-gtk.tar.gz"
  [[ -f "$gtk" ]] && { cp "$gtk" "$DIST/$id-gtk-$VER.tar.gz"; say "$id-gtk-$VER.tar.gz"; }
done

# the whole repo: the install path the README documents
src_out="$DIST/quantum-theme-$VER.tar.gz"
if [[ -d .git ]] && command -v git >/dev/null; then
  git archive --format=tar.gz --prefix="quantum-theme-$VER/" -o "$src_out" HEAD
else
  tar czf "$src_out" "${TARFLAGS[@]}" --exclude='./dist' --transform "s|^\.|quantum-theme-$VER|" .
fi
say "$(basename "$src_out") ($(du -h "$src_out" | cut -f1))"

( cd "$DIST" && sha256sum ./*.tar.gz > SHA256SUMS )
say "wrote $DIST/SHA256SUMS"

cat <<MSG

Upload map - three store products, each carrying one file per variant:

$("$0" --list)

On every product page, first line: the Global Theme does not pull in the decoration,
the Plasma style or the icon theme. Point at the source tarball and bin/install.sh.
MSG
