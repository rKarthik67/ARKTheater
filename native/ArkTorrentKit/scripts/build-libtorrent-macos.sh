#!/usr/bin/env bash
# Builds libtorrent-rasterbar (static lib, no Python bindings, no WebTorrent/
# OpenSSL) for macOS and vendors it into ../Vendor, alongside the Boost
# headers it needs (Asio/System are header-only - nothing to compile).
#
# Why not `brew install libtorrent-rasterbar`: on a non-default Homebrew
# prefix (no precompiled bottles available) that formula drags in Python
# bindings, which in turn pulls in boost-python3 and - on a cold cache -
# LLVM itself, just to produce headers/a library this project never uses
# the Python side of. Building libtorrent directly via its own CMake build
# is both lighter and avoids that path entirely.
set -euo pipefail

LIBTORRENT_VERSION="2.1.2"
BOOST_VERSION="1.89.0"
BOOST_VERSION_UNDERSCORE="1_89_0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$KIT_DIR/Vendor"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Fetching libtorrent-rasterbar $LIBTORRENT_VERSION"
curl -fL -o "$WORK_DIR/libtorrent.tar.gz" \
  "https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_VERSION}/libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz"
tar xzf "$WORK_DIR/libtorrent.tar.gz" -C "$WORK_DIR"

echo "==> Fetching Boost $BOOST_VERSION headers"
curl -fL -o "$WORK_DIR/boost.tar.gz" \
  "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_UNDERSCORE}.tar.gz"
tar xzf "$WORK_DIR/boost.tar.gz" -C "$WORK_DIR" "boost_${BOOST_VERSION_UNDERSCORE}/boost"

LIBTORRENT_SRC="$WORK_DIR/libtorrent-rasterbar-${LIBTORRENT_VERSION}"
BOOST_SRC="$WORK_DIR/boost_${BOOST_VERSION_UNDERSCORE}"
BUILD_DIR="$WORK_DIR/build-macos"
mkdir -p "$BUILD_DIR"

echo "==> Configuring libtorrent-rasterbar"
cmake -S "$LIBTORRENT_SRC" -B "$BUILD_DIR" -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_CXX_STANDARD_REQUIRED=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -Dbuild_tests=OFF -Dbuild_examples=OFF -Dbuild_tools=OFF \
  -Dpython-bindings=OFF \
  -Dwebtorrent=OFF \
  -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_GnuTLS=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_LibGcrypt=ON \
  -DBOOST_ROOT="$BOOST_SRC" \
  -DBoost_NO_SYSTEM_PATHS=ON \
  -DBoost_INCLUDE_DIR="$BOOST_SRC"

echo "==> Building libtorrent-rasterbar (this is the slow step)"
cmake --build "$BUILD_DIR" --target torrent-rasterbar -j "$(sysctl -n hw.ncpu)"

echo "==> Vendoring headers + static lib into $VENDOR_DIR"
rm -rf "$VENDOR_DIR/libtorrent" "$VENDOR_DIR/boost"
mkdir -p "$VENDOR_DIR/libtorrent/macos/lib" "$VENDOR_DIR/libtorrent/include" "$VENDOR_DIR/boost/include"
cp "$BUILD_DIR/libtorrent-rasterbar.a" "$VENDOR_DIR/libtorrent/macos/lib/"
cp -R "$LIBTORRENT_SRC/include/libtorrent" "$VENDOR_DIR/libtorrent/include/"
cp -R "$BOOST_SRC/boost" "$VENDOR_DIR/boost/include/"

echo "==> Done. Vendored at $VENDOR_DIR"
