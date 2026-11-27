#!/usr/bin/env bash
# Lint: the GDScript warnings the editor shows (integer division, shadowing, unused
# variables...), for every script in the project. Headless runs print them only with
# --check-only --debug, one script at a time. Prints each warning with its file, then
# LINT PASS or LINT FAIL; exit 1 on any warning or error.
# Run from anywhere: bash src/tools/lint.sh
set -u
cd "$(dirname "$0")/../.."
out=$(mktemp)
found=0
for f in $(find src tests -name '*.gd' | sort); do
	timeout 60 godot --headless --path . --check-only --debug --script "res://$f" > "$out" 2>&1
	if grep -qE "WARNING|ERROR" "$out"; then
		grep -E "WARNING|ERROR" -A1 "$out" | sed "s|^|$f: |"
		found=1
	fi
done
rm -f "$out"
if [ "$found" -eq 0 ]; then
	echo "LINT PASS"
else
	echo "LINT FAIL"
	exit 1
fi
