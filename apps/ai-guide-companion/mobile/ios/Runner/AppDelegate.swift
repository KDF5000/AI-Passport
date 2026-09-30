import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard
      let registrar = engineBridge.pluginRegistry.registrar(
        forPlugin: "GuideCompanionBackgroundExecution"
      )
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.kdf5000.guideCompanion/background",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "begin":
        let arguments = call.arguments as? [String: Any]
        let reason = arguments?["reason"] as? String ?? "Passport voice question"
        result(self.beginBackgroundTask(named: reason))
      case "end":
        self.endBackgroundTask()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func beginBackgroundTask(named reason: String) -> Bool {
    if backgroundTask != .invalid {
      return true
    }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: reason) {
      [weak self] in
      self?.endBackgroundTask()
    }
    return backgroundTask != .invalid
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else {
      return
    }
    let task = backgroundTask
    backgroundTask = .invalid
    UIApplication.shared.endBackgroundTask(task)
  }
}
