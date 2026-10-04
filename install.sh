#!/usr/bin/env bash
# Convenience wrapper. The real script is bin/install.sh; it needs a variant:
#   ./install.sh --variant light
#   ./install.sh --variant dark
# or run variants/<slug>/install.sh, which infers the variant from the path.
exec "$(dirname "$(readlink -f "$0")")/bin/install.sh" "$@"
