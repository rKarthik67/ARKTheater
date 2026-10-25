import Flutter
import UIKit
import AVFoundation
import AVKit

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

    let airPlayChannel = FlutterMethodChannel(
      name: "ark_theater/airplay",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    airPlayChannel.setMethodCallHandler { call, result in
      guard call.method == "showRoutePicker" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard #available(iOS 11.0, *) else {
        result(FlutterError(code: "unsupported", message: "AirPlay requires iOS 11 or newer.", details: nil))
        return
      }
      DispatchQueue.main.async {
        do {
          try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
          try AVAudioSession.sharedInstance().setActive(true)
        } catch {
          // The active video player may already own the audio session. The
          // picker can still be shown, so this is intentionally non-fatal.
        }
        guard let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .flatMap({ $0.windows })
          .first(where: { $0.isKeyWindow }), let view = window.rootViewController?.view else {
          result(FlutterError(code: "no_window", message: "Could not present the AirPlay picker.", details: nil))
          return
        }
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.prioritizesVideoDevices = true
        picker.alpha = 0.01
        view.addSubview(picker)
        // AVRoutePickerView is a container UIView. Its tappable route button
        // is a private descendant UIControl, so dispatch the action to that
        // control rather than attempting to send an action to the container.
        // This is the same interaction as tapping the visible route picker.
        guard let routeButton = self.firstControl(in: picker) else {
          picker.removeFromSuperview()
          result(FlutterError(code: "picker_unavailable", message: "Could not open the AirPlay picker.", details: nil))
          return
        }
        routeButton.sendActions(for: .touchUpInside)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          picker.removeFromSuperview()
        }
        result(nil)
      }
    }
  }

  private func firstControl(in view: UIView) -> UIControl? {
    if let control = view as? UIControl { return control }
    for subview in view.subviews {
      if let control = firstControl(in: subview) { return control }
    }
    return nil
  }
}
