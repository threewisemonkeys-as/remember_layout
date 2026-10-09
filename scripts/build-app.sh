#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/module-cache"

swift build -c release --product Remember --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox
binary_dir="$(swift build -c release --show-bin-path --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox)"
app_dir="$project_dir/dist/Remember.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" .build/module-cache
cp "$binary_dir/Remember" "$app_dir/Contents/MacOS/Remember"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"

swiftc -module-cache-path .build/module-cache scripts/GenerateIcon.swift -o .build/generate-icon
.build/generate-icon "$project_dir/dist/Remember.iconset" "$app_dir/Contents/Resources/Remember.icns"
codesign --force --sign - --identifier com.rememberlayout.Remember "$app_dir"
codesign --verify --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$project_dir/dist/Remember.zip"
printf 'Built %s\n' "$app_dir"
