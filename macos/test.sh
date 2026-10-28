#!/bin/bash
# Gate for macos/: style, build (warnings are errors), tests. Extra arguments go to `swift test`,
# e.g. ./test.sh --filter ProcessRunner. SKILLCASK_BIN=<path> also runs the contract tests.
set -euo pipefail
cd "$(dirname "$0")"
extra=()
case "$(xcode-select -p 2>/dev/null)" in
*CommandLineTools*)
    # The Command Line Tools ship swift-testing outside the default search paths.
    dev=/Library/Developer/CommandLineTools/Library/Developer
    extra=(-Xswiftc -F"$dev/Frameworks" -Xlinker -rpath -Xlinker "$dev/Frameworks" -Xlinker -rpath -Xlinker "$dev/usr/lib") ;;
esac
swift format lint --strict --recursive --parallel Sources Tests Package.swift
swift build -Xswiftc -warnings-as-errors ${extra[@]+"${extra[@]}"}
swift test -Xswiftc -warnings-as-errors ${extra[@]+"${extra[@]}"} "$@"
