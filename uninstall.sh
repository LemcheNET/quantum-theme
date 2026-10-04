#!/usr/bin/env bash
# Convenience wrapper. The real script is bin/uninstall.sh; it needs a variant:
#   ./uninstall.sh --variant light
#   ./uninstall.sh --variant dark
# or run variants/<slug>/uninstall.sh, which infers the variant from the path.
exec "$(dirname "$(readlink -f "$0")")/bin/uninstall.sh" "$@"
