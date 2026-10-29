#!/bin/bash
# Gate for macos/: style, build (warnings are errors), tests. Extra arguments go to `swift test`,
# e.g. ./test.sh --filter ProcessRunner. SKILLCASK_BIN=<path> also runs the contract tests.
set -euo pipefail
cd "$(dirname "$0")"
# Xcode's toolchain only: SwiftUI's macro plugins (`@State`, `@Entry`, `#Preview`) ship with Xcode, not with the
# Command Line Tools. `xcrun` honours DEVELOPER_DIR and xcode-select.
case "$(xcrun --find swift 2>/dev/null)" in
*/Xcode*.app/Contents/Developer/*) ;;
*)
    echo "test.sh: Skillcask for Mac needs Xcode: the @Entry and #Preview macro plugins ship only with Xcode; sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1 ;;
esac
swift format lint --strict --recursive --parallel Sources Tests Package.swift
# -warnings-as-errors misses diagnostics the compiler downgrades (e.g. under @preconcurrency), so any compiler
# warning line in the build or test output fails the gate too. swiftc colours diagnostics even into a pipe, so the
# escape codes are stripped before counting. Only files that compile in this run report: an incremental build hides
# warnings in unchanged files, so run on a clean build (`swift package clean`, or `--scratch-path`) before
# trusting a 0. CI's `macos-app` job (.github/workflows/ci.yml) runs this script on a clean checkout.
log=$(mktemp -t skillcask-test)
trap 'rm -f "$log"' EXIT
swift build -Xswiftc -warnings-as-errors 2>&1 | tee "$log"
swift test -Xswiftc -warnings-as-errors "$@" 2>&1 | tee -a "$log"
warnings=$(sed $'s/\e\\[[0-9;]*m//g' "$log" | grep -cE ':[0-9]+:[0-9]+: warning:' || true)
if [ "$warnings" -gt 0 ]; then
    echo "test.sh: $warnings compiler warning(s) above; the gate allows none." >&2
    exit 1
fi
