import ExpoModulesCore
import UIKit
import os

// Binary distribution: the engine is a separate module (prebuilt xcframework).
// Source build: engine + shim are one module and this import must not exist.
// See MoBGLocationModule.swift for the full note.
#if MOBG_BINARY
import MoBGLocationEngine
#endif

/// The unconditional-early-revival home (i4c). Registered via
/// `expo-module.config.json` `appleAppDelegateSubscribers`, so
/// `didFinishLaunchingWithOptions` runs at EVERY launch — including a
/// background relaunch by a region-exit/SLC event — before and independent of
/// the JS runtime (module `OnCreate` is JS-gated and hostage to JS health; this
/// is not).
///
/// Never reads `launchOptions[.location]` (deprecated in iOS 26) — revival
/// gates on our own persisted `wasTracking` (the F1 code consequence).
public final class MoBGLocationAppDelegateSubscriber: ExpoAppDelegateSubscriber {
  private static let log = Logger(subsystem: "expo.modules.mobglocation", category: "revival")

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // Wake forensics context (docs/ios/03 §4 failure axes): Background App
    // Refresh off historically disabled location relaunches; Low Power Mode
    // changes fix cadence — both belong in every revival log.
    let state = application.applicationState == .background ? "background" : "foreground"
    let refresh: String
    switch application.backgroundRefreshStatus {
    case .available: refresh = "available"
    case .denied: refresh = "denied"
    case .restricted: refresh = "restricted"
    @unknown default: refresh = "unknown"
    }
    let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    Self.log.notice("didFinishLaunching state=\(state, privacy: .public) backgroundRefresh=\(refresh, privacy: .public) lowPower=\(lowPower) — running revival")
    // Route through the Foundation-only facade so this shim references no engine
    // internals (the binary boundary; internal/public/ios-boundary.md).
    MoBGEngine.shared.reviveAtLaunch()
    return true
  }
}
