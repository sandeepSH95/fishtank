#!/bin/sh
# Builds the vendored libprojectM (vendor/projectm, git submodule) as dylibs and
# installs headers + libs into vendor/dist for the app to link against.
# libprojectM is LGPL-2.1 — we link it dynamically; see THIRD-PARTY-NOTICES.md.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/vendor/projectm"
BUILD="$SRC/build"
DIST="$REPO_ROOT/vendor/dist"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "vendor/projectm is empty — run: git submodule update --init --recursive --depth 1" >&2
    exit 1
fi

cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DENABLE_PLAYLIST=ON \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.4 \
    "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64"
cmake --build "$BUILD" --parallel "$(sysctl -n hw.ncpu)"
cmake --install "$BUILD" --prefix "$DIST"

# Xcode embeds from vendor/dist/embed: real files (symlinks resolved) named to
# match each dylib's @rpath install name.
mkdir -p "$DIST/embed"
cp -f "$DIST/lib/libprojectM-4.4."*.dylib "$DIST/embed/libprojectM-4.4.dylib"
cp -f "$DIST/lib/libprojectM-4-playlist.4."*.dylib "$DIST/embed/libprojectM-4-playlist.4.dylib"

echo
echo "Installed into $DIST:"
ls "$DIST/lib/"*.dylib "$DIST/embed/"
