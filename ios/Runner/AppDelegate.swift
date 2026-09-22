import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "ark_theater/display",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getBrightness":
        result(Double(UIScreen.main.brightness))
      case "setBrightness":
        guard let value = call.arguments as? NSNumber else {
          result(FlutterError(code: "invalid_brightness", message: "Expected a number", details: nil))
          return
        }
        UIScreen.main.brightness = CGFloat(min(1, max(0, value.doubleValue)))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
