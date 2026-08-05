#!/bin/sh
# Builds the Release app and packages a versioned zip into dist/.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION=$(sed -n 's/ *MARKETING_VERSION: //p' project.yml)
APP="DerivedData/Build/Products/Release/Fishtank.app"
ZIP="dist/Fishtank-$VERSION-beta.zip"

xcodegen generate
xcodebuild -project Fishtank.xcodeproj -scheme Fishtank -configuration Release \
    -derivedDataPath DerivedData ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build | grep -E 'BUILD (SUCCEEDED|FAILED)'

lipo -info "$APP/Contents/MacOS/Fishtank"
codesign --verify --deep --strict "$APP"

mkdir -p dist
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "Packaged $ZIP"
shasum -a 256 "$ZIP"
