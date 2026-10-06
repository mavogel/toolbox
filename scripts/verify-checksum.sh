#!/bin/ash
# shellcheck shell=dash
# Usage: verify-checksum.sh <file> <sums-file>
# Checks <file> against a "<sha256>  <name>" list and fails if it is not listed
# (sha256sum -c alone would pass on an empty list).
set -eu
line=$(awk -v f="$1" '$2 == f { print $1 "  " $2 }' "$2")
[ -n "$line" ] || { echo "no checksum listed for $1" >&2; exit 1; }
echo "$line" | sha256sum -c -
