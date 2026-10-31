// swift-tools-version:5.9
import Foundation
import PackageDescription

// Vendored via scripts/build-libtorrent-macos.sh (gitignored - see that
// script's own comment for why this isn't `brew install
// libtorrent-rasterbar`: on this machine's non-default Homebrew prefix,
// that formula has no precompiled bottle and drags in Python bindings
// - and therefore LLVM - just to produce a library this project never
// uses the Python side of).
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let vendorDir = packageDir.appendingPathComponent("Vendor")
let libtorrentIncludeDir = vendorDir.appendingPathComponent("libtorrent/include").path
let libtorrentLibDir = vendorDir.appendingPathComponent("libtorrent/macos/lib").path
let boostIncludeDir = vendorDir.appendingPathComponent("boost/include").path

// Must match the defines scripts/build-libtorrent-macos.sh's CMake build
// actually compiled libtorrent-rasterbar.a with (see its CMakeFiles/
// torrent-rasterbar.dir/flags.make) - config.hpp branches on these (e.g.
// TORRENT_USE_RTC) regardless of whether SPM or CMake is doing the
// compiling, so a mismatch here either fails to compile or - worse -
// silently mismatches the .a's actual ABI.
let libtorrentDefines: [String] = [
  "-DBOOST_ASIO_HAS_STD_CHRONO",
  "-DBOOST_ASIO_NO_DEPRECATED",
  "-DBOOST_EXCEPTION_DISABLE",
  "-DBOOST_SYSTEM_USE_UTF8",
  "-DTORRENT_ABI_VERSION=2",
  "-DTORRENT_USE_RTC=0",
  "-D_FILE_OFFSET_BITS=64",
]

let macHeaderSearchPaths: [String] = [
  "-I\(libtorrentIncludeDir)",
  "-I\(boostIncludeDir)",
] + libtorrentDefines
let macLinkerFlags: [String] = [
  "-L\(libtorrentLibDir)",
  "-ltorrent-rasterbar",
]

// iOS links against native/ArkTorrentKit/Vendor/libtorrent/LibtorrentRasterbar.xcframework
// (see scripts/build-libtorrent-ios.sh), but NOT via an SPM binaryTarget:
// that path compiled fine but silently failed to make it onto the actual
// Xcode link line (every libtorrent symbol came back undefined), a known
// rough edge in how Xcode's local-SPM-package integration forwards
// intermediate-target binaryTarget dependencies. Linking it directly as an
// Xcode project "Link Binary With Libraries" entry (see
// scripts/add_package_ios.rb-equivalent wiring) is the reliable path real
// Xcode projects use for vendored xcframeworks, so this target only needs
// the (shared, architecture-independent) header search path - the actual
// link happens at the Xcode project level, not through SPM.
let iosHeaderSearchPaths: [String] = [
  "-I\(libtorrentIncludeDir)",
  "-I\(boostIncludeDir)",
] + libtorrentDefines

let package = Package(
  name: "ArkTorrentKit",
  platforms: [.macOS(.v12), .iOS(.v15)],
  products: [
    .library(name: "ArkTorrentKit", targets: ["ArkTorrentKit"]),
  ],
  targets: [
    .target(
      name: "CArkTorrent",
      path: "Sources/CArkTorrent",
      publicHeadersPath: "include",
      cSettings: [
        .unsafeFlags(macHeaderSearchPaths, .when(platforms: [.macOS])),
        .unsafeFlags(iosHeaderSearchPaths, .when(platforms: [.iOS])),
      ],
      cxxSettings: [
        .unsafeFlags(macHeaderSearchPaths, .when(platforms: [.macOS])),
        .unsafeFlags(iosHeaderSearchPaths, .when(platforms: [.iOS])),
      ],
      linkerSettings: [
        .unsafeFlags(macLinkerFlags, .when(platforms: [.macOS])),
        // libtorrent's ip_notifier.cpp watches for network-interface changes
        // via SCDynamicStore on both Apple platforms.
        .linkedFramework("SystemConfiguration"),
      ]
    ),
    // Platform-agnostic, Flutter-independent core (the HTTP range server +
    // VLC hand-off) - split out from ArkTorrentKit so it (and the libtorrent
    // engine) can be exercised directly in a plain `swift run` smoke test,
    // without needing Flutter's framework linked in.
    .target(
      name: "ArkTorrentCore",
      dependencies: ["CArkTorrent"],
      path: "Sources/ArkTorrentCore"
    ),
    .target(
      name: "ArkTorrentKit",
      dependencies: ["CArkTorrent", "ArkTorrentCore"],
      path: "Sources/ArkTorrentKit"
    ),
  ],
  cxxLanguageStandard: .cxx17
)
