# Changelog

## Unpublished

## 0.1.4 — 2026-07-17

### 🐛 Bug fixes

- **Android: fixed a crash on the first park of a non-whitelisted install.** The
  stationary Doze-poll (docs/11) scheduled its heartbeat with
  `setExactAndAllowWhileIdle`, which throws `SecurityException` on Android 12+
  unless the app holds exact-alarm capability. That capability is auto-granted
  when the app is exempt from battery optimization — the SDK's recommended
  deep-Doze setup — so the bug was invisible on whitelisted field devices and
  only surfaced on a fresh consumer install before the user grants the exemption:
  the OS crash-looped the app ("… keeps stopping") at the first stationary snap-in.
  The poll now guards the call with `AlarmManager.canScheduleExactAlarms()` and
  falls back to the inexact `setAndAllowWhileIdle` when the capability is missing.
  The heartbeat relaxes to Doze maintenance-window cadence (losing the exact 60-s
  precision that catches a *silent* rolling drive-away from deep Doze) until the
  app is battery-whitelisted or the user enables **Settings → Alarms & reminders**,
  at which point the exact poll returns automatically. See AND-10 in
  `docs/06-pitfalls.md`.

### 💡 Others

- **Android manifest declares `SCHEDULE_EXACT_ALARM`** (plugin) so the exact
  poll can be granted. The SDK never uses the Play-restricted `USE_EXACT_ALARM`;
  apps shipping on Google Play should note the exact-alarm policy declaration.

## 0.1.3 — 2026-07-16

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

- **iOS: the combined `requestPermissions({ background, activity })` form now
  runs the full permission ladder.** Since 0.1.2 (and earlier), passing
  `activity: true` on iOS ran ONLY the Motion & Fitness prompt — the location
  stages were skipped entirely, so the documented one-shot form from the README
  never obtained When-In-Use or Always authorization. The stages now chain to
  match Android exactly: foreground location always first → Always upgrade when
  `background` and foreground was granted → Motion & Fitness when `activity`
  and foreground was granted → one merged `PermissionStatus`. Behaviour note:
  the `{ activity: true }`-only form now (correctly) requests When-In-Use
  before the motion prompt instead of skipping location. The chained upgrade
  also waits for the app to re-activate after the When-In-Use alert before
  requesting Always — asking while the alert was still dismissing could
  intermittently skip the Always prompt AND burn iOS's once-per-install
  upgrade ask, leaving the install permanently stuck at When-In-Use.
- **npm package name is stamped correctly.** The packaging template still
  carried the unscoped pre-release name; the packed tarball and its
  `package.json` now say `@aalillou/mo-bg-location` without a manual rename
  step at publish time.
- **`dxStepCadence` now decays instead of freezing.** Cadence was cached on the
  last step event, so it stayed at its last value (e.g. 75/min) while the user
  stood still — masquerading as walking on still rows (seen in 2026-06-19 data).
  It's now evaluated at read time over a rolling window, decaying to 0 once a
  window passes with no steps. Logging-only; no tracking behaviour change.

### 💡 Others
