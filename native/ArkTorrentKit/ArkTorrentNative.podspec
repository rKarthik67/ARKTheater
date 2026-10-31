Pod::Spec.new do |s|
  s.name             = 'ArkTorrentNative'
  s.version          = '1.0.0'
  s.summary          = 'Vendored libtorrent-rasterbar for ArkTorrentKit (iOS).'
  s.description      = <<-DESC
    Links the libtorrent-rasterbar XCFramework built by
    scripts/build-libtorrent-ios.sh. CocoaPods (not the ArkTorrentKit Swift
    package) owns this link step on iOS: a `vendored_frameworks` entry is
    the proven mechanism this project already relies on for every other
    vendored XCFramework (media_kit's Mpv.framework etc.) - SPM's own
    binaryTarget / direct-Xcode-project-reference paths were both tried and
    didn't make it onto the actual link line (see native/ArkTorrentKit's
    Package.swift comments).
  DESC
  s.homepage         = 'https://github.com/ark-theater/ark-theater'
  s.license          = { :type => 'BSD-3-Clause (libtorrent-rasterbar)' }
  s.author           = { 'ARK Theater' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.vendored_frameworks = 'Vendor/libtorrent/LibtorrentRasterbar.xcframework'
  s.frameworks       = 'SystemConfiguration'
  s.requires_arc     = false
end
