/// Shifts every timestamp in an SRT or WebVTT subtitle file's text by
/// [offsetSeconds] (positive = subtitles appear later, negative = earlier),
/// clamping each resulting timestamp at zero.
///
/// Used to manually correct subtitle timing that doesn't quite line up
/// with the video's speech - by far the most common cause is that the
/// subtitle file was made for a slightly different release/cut of the
/// title (different intro length, different edit) than the one actually
/// playing, which shows up as one fixed, uniform drift across the whole
/// file rather than random per-line errors. A different downloaded
/// subtitle isn't guaranteed to fix that (it might be timed for yet
/// another cut), but nudging the offset by a fraction of a second always
/// will, since the drift is constant.
///
/// Matches both SRT's `00:00:01,000` and WebVTT's `00:00:01.000` full
/// hour:minute:second forms (the separator, comma or dot, is preserved).
String shiftSubtitleTimings(String content, double offsetSeconds) {
  if (offsetSeconds == 0) return content;
  final offsetMs = (offsetSeconds * 1000).round();
  final timestamp = RegExp(r'(\d{2}):(\d{2}):(\d{2})([.,])(\d{3})');

  String pad(int value, int width) => value.toString().padLeft(width, '0');

  return content.replaceAllMapped(timestamp, (match) {
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final separator = match.group(4)!;
    final millis = int.parse(match.group(5)!);

    var totalMs = (((hours * 60 + minutes) * 60 + seconds) * 1000 + millis) + offsetMs;
    if (totalMs < 0) totalMs = 0;

    final h = totalMs ~/ 3600000;
    final afterHours = totalMs % 3600000;
    final m = afterHours ~/ 60000;
    final afterMinutes = afterHours % 60000;
    final s = afterMinutes ~/ 1000;
    final ms = afterMinutes % 1000;

    return '${pad(h, 2)}:${pad(m, 2)}:${pad(s, 2)}$separator${pad(ms, 3)}';
  });
}
