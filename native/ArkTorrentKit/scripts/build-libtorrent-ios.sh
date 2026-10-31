#!/usr/bin/env bash
# Cross-compiles libtorrent-rasterbar (static lib, no Python bindings, no
# WebTorrent/OpenSSL) for iOS device (arm64) and iOS Simulator (x86_64 -
# this Mac is Intel, so the Simulator runs x86_64, not arm64), then bundles
# both slices + headers into an XCFramework vendored at ../Vendor. See
# build-libtorrent-macos.sh for why this isn't a Homebrew/precompiled
# dependency.
set -euo pipefail

LIBTORRENT_VERSION="2.1.2"
BOOST_VERSION="1.89.0"
BOOST_VERSION_UNDERSCORE="1_89_0"
IOS_DEPLOYMENT_TARGET="15.0"

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

# $1 = slice name (device|simulator), $2 = arch, $3 = sdk (iphoneos|iphonesimulator)
build_slice() {
  local slice="$1" arch="$2" sdk="$3"
  local build_dir="$WORK_DIR/build-ios-$slice"
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  echo "==> Configuring libtorrent-rasterbar for iOS $slice ($arch)"
  cmake -S "$LIBTORRENT_SRC" -B "$build_dir" -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
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

  echo "==> Building libtorrent-rasterbar for iOS $slice (this is the slow step)"
  cmake --build "$build_dir" --target torrent-rasterbar -j "$(sysctl -n hw.ncpu)"

  mkdir -p "$VENDOR_DIR/libtorrent/ios-$slice/lib"
  cp "$build_dir/libtorrent-rasterbar.a" "$VENDOR_DIR/libtorrent/ios-$slice/lib/"
}

build_slice "device" "arm64" "iphoneos"
build_slice "simulator" "x86_64" "iphonesimulator"

echo "==> Vendoring headers"
rm -rf "$VENDOR_DIR/libtorrent/include" "$VENDOR_DIR/boost"
mkdir -p "$VENDOR_DIR/libtorrent/include" "$VENDOR_DIR/boost/include"
cp -R "$LIBTORRENT_SRC/include/libtorrent" "$VENDOR_DIR/libtorrent/include/"
cp -R "$BOOST_SRC/boost" "$VENDOR_DIR/boost/include/"

echo "==> Done. Vendored at $VENDOR_DIR"
echo "    device:    $VENDOR_DIR/libtorrent/ios-device/lib/libtorrent-rasterbar.a"
echo "    simulator: $VENDOR_DIR/libtorrent/ios-simulator/lib/libtorrent-rasterbar.a"
