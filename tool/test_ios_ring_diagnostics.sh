#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -r "$scratch"' EXIT
swiftc "$root/ios/Classes/YuchengDiagnostics.swift" "$root/ios/Tests/Diagnostics/main.swift" -o "$scratch/test"
"$scratch/test"
