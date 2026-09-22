import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/platform_files.dart';

/// File I/O for Settings > Library's "Export Watchlist" / "Import
/// Watchlist" - the actual share-sheet / file-picker mechanics. The JSON
/// shape itself (what's *in* the file) is [WatchlistService]'s job; this
/// class only gets that JSON text onto and off of the filesystem so it can
/// travel to another device.
class WatchlistBackupService {
  /// Stages the export as a real temp file where there's a filesystem, and
  /// returns null on web so the caller can fall back to sharing bytes.
  Future<String?> writeTempFileOrNull(String timestamp, String jsonText) =>
      writeTempString('ark_theater_watchlist_$timestamp.json', jsonText);

  /// Writes [jsonText] to a temp file and opens the native share sheet
  /// (AirDrop, Messages, Mail, "Save to Files"/a cloud drive, etc. -
  /// whatever the OS offers) so the user can send the exported watchlist
  /// to another device. Returns `false` if the user dismissed the share
  /// sheet without picking anything - that's a normal cancel, not an error.
  ///
  /// [sharePositionOrigin] anchors the native share popover on macOS/iPad -
  /// both require a non-zero rect (in the source view's coordinate space)
  /// or the platform call throws instead of opening the sheet. Phones
  /// ignore it, so it's safe to omit there, but callers on every platform
  /// should pass one (see settings_screen.dart's `_shareOrigin`).
  Future<bool> exportAndShare(String jsonText, {Rect? sharePositionOrigin}) async {
    // Colons aren't safe in filenames on every platform this app targets
    // (notably Windows), hence the swap below.
    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final path = await writeTempFileOrNull(timestamp, jsonText);

    // Web can't stage a temp file, so the JSON is handed to the share sheet
    // as bytes instead of a path. Everywhere else keeps the real file, which
    // is what makes "Save to Files"/a cloud drive offer a sensible filename.
    final xFile = path != null
        ? XFile(path, mimeType: 'application/json', name: 'ark_theater_watchlist.json')
        : XFile.fromData(
            Uint8List.fromList(utf8.encode(jsonText)),
            mimeType: 'application/json',
            name: 'ark_theater_watchlist.json',
          );

    final result = await Share.shareXFiles(
      [xFile],
      subject: 'ARKTheater Watchlist',
      text: 'My ARKTheater watchlist - open this file with "Import Watchlist" in the '
          'app on another device to merge it in.',
      // Falls back to a tiny 1x1 rect near the origin rather than omitting
      // this - macOS/iPad reject a null/zero origin outright, and a small
      // valid rect is always "within the coordinate space of the source
      // view" no matter how the caller's layout turns out.
      sharePositionOrigin: sharePositionOrigin ?? const Rect.fromLTWH(0, 0, 1, 1),
    );
    return result.status == ShareResultStatus.success;
  }

  /// Opens the native file-open dialog restricted to `.json` files and
  /// returns the picked file's text content, or `null` if the user
  /// cancelled the picker.
  Future<String?> pickAndReadJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;

    // Mobile/desktop file pickers usually hand back bytes directly; a few
    // platforms only give a filesystem path instead, so fall back to
    // reading it ourselves when bytes weren't provided.
    final bytes = picked.bytes;
    if (bytes != null) return utf8.decode(bytes);
    final path = picked.path;
    if (path != null) return readFileAsString(path);
    return null;
  }
}
