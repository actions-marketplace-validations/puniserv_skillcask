#!/bin/sh
# `swift test`. The Command Line Tools ship swift-testing outside the default search paths, so
# without Xcode the framework and its interop library have to be passed explicitly.
set -eu
cd "$(dirname "$0")"
dev=/Library/Developer/CommandLineTools/Library/Developer
case "$(xcode-select -p 2>/dev/null)" in
*CommandLineTools*)
    exec swift test -Xswiftc -F"$dev/Frameworks" \
        -Xlinker -rpath -Xlinker "$dev/Frameworks" -Xlinker -rpath -Xlinker "$dev/usr/lib" "$@" ;;
*) exec swift test "$@" ;;
esac
