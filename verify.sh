#!/usr/bin/env bash
# Convenience wrapper. The real script is bin/verify.sh; it needs a variant:
#   ./verify.sh --variant light
#   ./verify.sh --variant dark
# or run variants/<slug>/verify.sh, which infers the variant from the path.
exec "$(dirname "$(readlink -f "$0")")/bin/verify.sh" "$@"
