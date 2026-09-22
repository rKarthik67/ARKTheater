import 'dart:typed_data';

/// Web (and any other dart:io-less platform): there is no temp directory to
/// write to, so both of these report "couldn't do it" and callers fall back
/// to an in-memory path. See platform_files.dart.
Future<String?> writeTempBytes(String fileName, Uint8List bytes) async => null;

Future<String?> writeTempString(String fileName, String contents) async => null;

Future<String?> readFileAsString(String path) async => null;
