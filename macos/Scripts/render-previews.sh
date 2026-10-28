#!/bin/bash
# Renders the registered SwiftUI previews to PNG in light and dark at 2x for the design gate.
#   macos/Scripts/render-previews.sh [--renderer host|image] [id-or-prefix ...]   # e.g. ... probe
#   macos/Scripts/render-previews.sh --list
# Output: macos/.build/renders/<id>/{light,dark}/<state>.png (git-ignored). Exits non-zero when the
# build fails or any PNG is missing or under 5 KB.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift run SkillcaskRender --out .build/renders "$@"
