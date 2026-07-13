import ExpoModulesCore
import os

// In the BINARY distribution the engine ships as a prebuilt xcframework, so it is
// a SEPARATE module and must be imported. In the SOURCE build (example app, tests)
// the podspec compiles engine + shim into one module, where the import would not
// resolve. The binary podspec defines MOBG_BINARY via
// SWIFT_ACTIVE_COMPILATION_CONDITIONS; the source podspec does not.
#if MOBG_BINARY
import MoBGLocationEngine
#endif

/// iOS Expo module surface for `mo-bg-location` — the thin JS shim. Every engine
/// operation is delegated to `MoBGEngine` (the Foundation-only binary boundary;
/// see internal/public/ios-boundary.md). This file is deliberately pure
/// forwarding + Expo event/promise/exception translation: no algorithms and no
/// engine types cross into it, so it stays source in the published package and
/// recompiles against the host app's ExpoModulesCore.
///
/// Method signatures match `src/MoBGLocationModule.ts` and the Android
/// `MoBGLocationModule.kt`. Implemented: configure / start / stop /
/// getCurrentPosition / requestPermissions / getPermissions. Still stubbed: the
/// Android-only power ledger (getPowerStats/resetPowerStats).
///
/// Everything runs on the main queue, matching the engine's confinement.
public class MoBGLocationModule: Module {
  /// `.notice` so lines persist to the on-device store and survive a
  /// `log collect` harvest (docs/ios/05 §5 / 06 §3).
  private static let log = Logger(subsystem: "expo.modules.mobglocation", category: "module")

  private let engine = MoBGEngine.shared

  public func definition() -> ModuleDefinition {
    Name("MoBGLocation")

    OnCreate {
      Self.log.notice("MoBGLocation module created (engine tracking=\(self.engine.isTracking))")
    }

    Events("onLocation", "onMotionChange", "onMotionWake", "onDiagnostic")

    AsyncFunction("configure") { (config: [String: Any]) in
      self.engine.configure(config)
    }.runOnQueue(.main)

    AsyncFunction("start") { () throws in
      // Engine → JS bridges: set the taps, then start. The engine owns listener
      // registration/removal; these closures are pure forwarding to sendEvent.
      self.engine.onLocation = { [weak self] event in self?.sendEvent("onLocation", event) }
      self.engine.onMotionChange = { [weak self] event in self?.sendEvent("onMotionChange", event) }
      self.engine.onMotionWake = { [weak self] event in self?.sendEvent("onMotionWake", event) }
      self.engine.onDiagnostic = { [weak self] event in self?.sendEvent("onDiagnostic", event) }
      do {
        try self.engine.start()
      } catch {
        throw Self.expoError(from: error)
      }
    }.runOnQueue(.main)

    AsyncFunction("stop") {
      self.engine.stop()
    }.runOnQueue(.main)

    AsyncFunction("getCurrentPosition") { (promise: Promise) in
      self.engine.getCurrentPosition { result in
        switch result {
        case .success(let event):
          promise.resolve(event)
        case .failure(let error):
          promise.reject(Self.expoError(from: error))
        }
      }
    }.runOnQueue(.main)

    AsyncFunction("requestPermissions") { (options: [String: Any], promise: Promise) in
      // Same JS ladder as Android: default = When-In-Use; `background: true`
      // runs the Always upgrade; `activity: true` runs the Motion & Fitness
      // prompt. The ladder itself lives in the engine.
      let background = (options["background"] as? Bool) == true
      let activity = (options["activity"] as? Bool) == true
      self.engine.requestPermissions(background: background, activity: activity) { permissions in
        promise.resolve(permissions)
      }
    }.runOnQueue(.main)

    AsyncFunction("getPermissions") { (promise: Promise) in
      // Read-only — never prompts (mirrors Android).
      promise.resolve(self.engine.permissions())
    }.runOnQueue(.main)

    // Android-only power ledger (docs/20) — explicit stubs so a JS call gets a
    // clear error instead of "method not found".
    AsyncFunction("getPowerStats") { () throws -> [String: Any] in
      do { return try self.engine.getPowerStats() } catch { throw Self.expoError(from: error) }
    }

    AsyncFunction("resetPowerStats") { () throws -> [String: Any] in
      do { return try self.engine.resetPowerStats() } catch { throw Self.expoError(from: error) }
    }

    OnDestroy {
      // JS context is going away — detach the JS bridges ONLY. Tracking (and a
      // parked stationary machine) belongs to the process-lifetime engine: a
      // JS reload or background context teardown must never stop it (the i4
      // ownership contract; pre-i4 this stopped the stream).
      DispatchQueue.main.async {
        self.engine.detachCallbacks()
      }
    }
  }

  /// Translate the Foundation-only engine errors into the JS-facing Expo
  /// exceptions. Keeping the taxonomy (and codes) at the shim boundary means no
  /// Expo type has to cross into the engine.
  private static func expoError(from error: Error) -> Exception {
    guard let engineError = error as? MoBGEngineError else {
      return EngineException(error.localizedDescription)
    }
    switch engineError {
    case .permissionDenied: return PermissionDeniedException()
    case .noLocation: return NoLocationException()
    case .locationFailed(let message): return LocationFailedException(message)
    case .notImplemented(let name): return NotYetImplementedException(name)
    case .licenseInvalid(let message): return LicenseException(message)
    // In the BINARY build the engine is a separate module compiled with library
    // evolution, so MoBGEngineError is resilient (non-frozen) and the compiler
    // requires this clause. Unreachable in practice: engine and shim ship
    // together at the same version.
    @unknown default: return EngineException(String(describing: engineError))
    }
  }
}

internal final class PermissionDeniedException: Exception, @unchecked Sendable {
  override var code: String { "ERR_PERMISSION_DENIED" }
  override var reason: String {
    "Foreground location permission has not been granted. Call requestPermissions() first."
  }
}

internal final class NoLocationException: Exception, @unchecked Sendable {
  override var code: String { "ERR_NO_LOCATION" }
  override var reason: String { "Location provider returned an invalid fix." }
}

internal final class LocationFailedException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_LOCATION" }
  override var reason: String { param }
}

/// Thrown by the not-yet-implemented (Android-only or later-slice) methods.
internal final class NotYetImplementedException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_NOT_IMPLEMENTED" }
  override var reason: String {
    "MoBGLocation.\(param) is not implemented on iOS yet."
  }
}

/// Defensive fallback for a non-`MoBGEngineError` surfacing at the boundary (the
/// engine only throws `MoBGEngineError`).
internal final class EngineException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_MOBG" }
  override var reason: String { param }
}

/// Phase 3 license gate (docs/22): a release build without a valid entitlement.
/// `param` is the customer-facing reason from the engine's license verdict.
internal final class LicenseException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_LICENSE" }
  override var reason: String { param }
}
