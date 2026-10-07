#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
binary="$(mktemp -t yucheng-completer)"
trap 'rm -f "$binary"' EXIT
swiftc "$root/ios/Classes/utils/Completer.swift" "$root/test/ios/completer/main.swift" -o "$binary"
"$binary"
