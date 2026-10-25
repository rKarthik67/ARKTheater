import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Opens Apple's native AirPlay route picker from the in-player action.
/// AVRoutePickerView itself is hosted by Runner because it must be presented
/// from an iOS UIView hierarchy, not from Flutter's widget tree.
class AirPlayService {
  AirPlayService._();

  static const _channel = MethodChannel('ark_theater/airplay');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> showRoutePicker() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('showRoutePicker');
  }
}
