import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Native platforms: the real filesystem implementations behind
/// platform_files.dart. path_provider is imported here rather than at the
/// call sites because it has no web implementation either -
/// getTemporaryDirectory() throws there.
Future<String?> writeTempBytes(String fileName, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<String?> writeTempString(String fileName, String contents) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(contents);
  return file.path;
}

Future<String?> readFileAsString(String path) => File(path).readAsString();
