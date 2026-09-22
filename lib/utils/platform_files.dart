/// Temp-file helpers that compile on every platform, including web.
///
/// `dart:io` does not exist in a browser, and importing it anywhere in the
/// reachable tree fails a web compile outright - a runtime `kIsWeb` guard
/// is not enough, because the failure happens while compiling, not while
/// running. So the two places this app genuinely touches the filesystem
/// (the splash chime, and watchlist export/import) go through this
/// conditional export instead.
///
/// The stub is the default and the dart:io version is opted into, rather
/// than the other way round: that way any future platform without dart:io
/// gets the safe no-op automatically instead of failing to build.
export 'platform_files_stub.dart' if (dart.library.io) 'platform_files_io.dart';
