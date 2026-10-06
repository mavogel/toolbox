#!/bin/sh
# Smoke test for the toolbox image. Mount it read-only and run as the image's
# default user:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/smoke.sh
#
# For every tool in the inventory it checks: on PATH, executable, and the check
# command exits 0. It also fails on uninventoried binaries in /usr/local/bin,
# running as root, and any setuid/setgid file.
INVENTORY=${INVENTORY:-/tests/inventory.txt}
fail=0
pass=0

report_fail() {
  echo "FAIL $1: $2"
  fail=$((fail + 1))
}

[ -r "$INVENTORY" ] || { echo "FAIL inventory: cannot read $INVENTORY"; exit 1; }

while IFS= read -r line; do
  case "$line" in '' | '#'*) continue ;; esac
  bin=${line%% *}
  check=${line#* }
  path=$(command -v "$bin" 2>/dev/null) || { report_fail "$bin" "not on PATH"; continue; }
  [ -x "$path" ] || { report_fail "$bin" "$path is not executable"; continue; }
  if sh -c "$check" >/dev/null 2>&1; then
    echo "PASS $bin"
    pass=$((pass + 1))
  else
    report_fail "$bin" "check failed: $check"
  fi
done < "$INVENTORY"

for f in /usr/local/bin/*; do
  name=${f##*/}
  grep -q "^$name " "$INVENTORY" || report_fail "$name" "uninventoried binary in /usr/local/bin"
done

[ "$(id -u)" != 0 ] || report_fail "user" "running as root"

suid=$(find / -xdev -type f -perm /6000 2>/dev/null)
[ -z "$suid" ] || report_fail "setuid" "setuid/setgid files present: $suid"

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
