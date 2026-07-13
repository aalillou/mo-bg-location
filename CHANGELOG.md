# Changelog

## Unpublished

### 🛠 Breaking changes

### 🎉 New features

- **Commercial license gate.** The native engine now enforces a signed offline
  entitlement. **Development stays free** — debug builds, the iOS simulator, and
  dev-signed device builds are fully functional with no key. A **release** build
  requires a `licenseKey` (config option), a `MOBG1.…` string issued by Aalillou
  and bound to your Android package name / iOS bundle identifier (one key covers
  both platforms). Without a valid key, `start()` fails loudly — Android rejects
  with code `ERR_LICENSE`, iOS throws a license error, each carrying the reason
  (missing / wrong-app / tampered / expired). The verdict re-validates from
  persisted config on every (re)start and on background/swipe-kill revival, so a
  revived service never tracks keyless. A test-only `licenseEnforceRelease` flag
  (tighten-only — it can only add enforcement) exercises the release path on a
  dev-signed rig. The key is a signed public statement, safe to ship in your JS
  bundle. See **Licensing** in the README and `LICENSE`.
- **3.7 ground-truth logging (Android, logging-only).** New `StepDetector`
  (`TYPE_STEP_DETECTOR`) and `ClassifierDiagnostics` stamp every `LocationEvent`
  with the raw verdict of each label source for the 3.7 day-test: `dxArActivity`
  (raw Activity Recognition), `dxAccelStill`, `dxStepCount`/`dxStepCadence`, and
  `dxSpeedClass` (GPS-speed-derived). These drive nothing — the fused `activity`/
  `isMoving` are unchanged; the columns exist only to validate a self-computed
  classifier against AR. See `docs/08-activity-recognition-decision.md`.
- **Dashboard ground-truth stream panel.** `example/dashboard/trip-map.html`
  gains a right-side list of the four label columns per location, with
  auto-highlight for accel-still-vs-speed-vehicle (red) and unknown-while-moving
  (amber).

### 🐛 Bug fixes

- **`dxStepCadence` now decays instead of freezing.** Cadence was cached on the
  last step event, so it stayed at its last value (e.g. 75/min) while the user
  stood still — masquerading as walking on still rows (seen in 2026-06-19 data).
  It's now evaluated at read time over a rolling window, decaying to 0 once a
  window passes with no steps. Logging-only; no tracking behaviour change.

### 💡 Others
