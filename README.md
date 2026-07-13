# mo-bg-location

Background geolocation for Expo / React Native with a self-computed activity
classifier and a battery-aware motion state machine. The native engine ships as
prebuilt binaries (Android `.aar`, iOS `.xcframework`); the JavaScript API and
Expo config plugin are open in this package.

> Commercial SDK — free in development/debug, license key required for release
> builds. See [Licensing](#licensing) below.

---

## Why mo-bg-location

Most background geolocation SDKs keep the GPS chip polling continuously — even
when parked — and depend on geofences or timed heartbeats to detect departure.
That pattern burns battery proportional to park duration and is fragile on
Android Doze, where the CPU wakes infrequently and network-based geofences
stall.

**mo-bg-location takes a different approach:**

- **GPS-independent wake from idle.** Departure detection is driven by the
  hardware significant-motion sensor (Android) and Apple's CLLocationUpdate
  stationarity engine (iOS 17+), not by GPS geofences. The motion trigger fires
  inside Doze at the hardware interrupt level — no GPS required to detect that
  the vehicle started moving.

- **Self-computed activity classifier.** Activity labels (`walking`,
  `in_vehicle`, `still`, …) come from our own classifier built on step counts,
  Doppler speed, and covering-ground logic — not from the OS activity
  recognition API, whose labels can lag by minutes and vary by device. Two
  selectable models: `residual` (Doppler/covering-ground, the default) and
  `steps` (GPS-free, instant label transitions, suited for fleet/driver apps
  where the meaningful on-foot signal is active walking).

- **Battery-aware stationary tiers.** Three automatic tiers — tight 60-second
  poll (first 45 min of a stop, catches the quick errand), relaxed 5-minute
  poll (longer stops), and deep-idle rare poll (overnight park, after 90 min of
  stillness). The deep-idle tier eliminates the overnight polling floor that
  otherwise drains the battery over an all-night park.

- **Measured wake latency.** On iOS with the `liveUpdates` arm: 4–22 s /
  10–77 m from wheels rolling to first location update in field tests. Classic
  geofence-exit approaches measured at ~60–90 s on the same hardware.

- **Delivery that survives a killed JS context.** The optional native RTDB sink
  writes location, motion, and diagnostic events from the native foreground
  service (Android) or `TrackingRuntime` (iOS) — with no JS alive. Useful for
  fleet or logistics apps that need a full track without a foreground UI.

---

## Install

```bash
npx expo install @aalillou/mo-bg-location
```

This is an Expo module with a config plugin. In a managed app, run a prebuild
so the plugin can apply the required Android permissions, foreground-service
declarations, and iOS background modes:

```bash
npx expo prebuild
```

### Supported Expo SDK range

Each release pins the Expo SDK range it is built against (native binaries are
compiled against a specific `expo-modules-core`). Installing outside the
supported range is not supported.

| mo-bg-location | Expo SDK |
|----------------|----------|
| (set per release) | (set per release) |

---

## Quick start

```ts
import {
  configure,
  requestPermissions,
  start,
  stop,
  onLocation,
  onMotionChange,
  onMotionWake,
} from 'mo-bg-location';

// 1. Configure before requesting permissions or starting
await configure({
  desiredAccuracy: 'high@5s',
  distanceFilter: 10,
  stopTimeout: 90,
  notificationTitle: 'Tracking active',
  notificationBody: 'Location tracking is running in the background.',
});

// 2. Request permissions
await requestPermissions({ background: true, activity: true });

// 3. Subscribe to events
const locSub = onLocation((e) => {
  console.log(e.latitude, e.longitude, e.activity, e.isMoving);
});

const motionSub = onMotionChange((e) => {
  // Fires on stationary ↔ moving transitions and label promotions
  console.log('motion:', e.isMoving, e.activity);
});

const wakeSub = onMotionWake((e) => {
  // Fires when the stationary engine wakes due to motion (reason, displacement)
  console.log('wake reason:', e.reason);
});

// 4. Start tracking
await start();

// 5. Stop and clean up
await stop();
locSub.remove();
motionSub.remove();
wakeSub.remove();
```

---

## Configuration reference

Pass a complete config object to `configure()` before calling `start()`. The
native side stashes it; re-calling `configure()` between runs is safe and is
the way to switch A/B flags without a rebuild.

```ts
await configure({
  // ── Core tracking ──────────────────────────────────────────────────────
  desiredAccuracy: 'high@5s', // 'high' | 'high@5s' | 'balanced'
  distanceFilter: 10,          // metres between updates while moving
  stopTimeout: 90,             // seconds of stillness before going stationary

  // ── Android foreground-service notification ────────────────────────────
  notificationTitle: 'Tracking active',
  notificationBody:  'Running in the background.',

  // ── Battery / stationary tiers ─────────────────────────────────────────
  deepIdleAfter: 90,           // minutes of stillness → deep idle (0 = disable)
  deepIdlePollInterval: 30,    // minutes between polls in deep idle
  tightPollWindowMinutes: 45,  // minutes of tight 60-second polling after a stop

  // ── Activity classifier ────────────────────────────────────────────────
  labelMode: 'residual',       // 'residual' (Doppler, default) | 'steps' (GPS-free)
  stepsModeQuietMs: 8000,      // ms of no step → in_vehicle  (steps model only)
  stepsStillWindowMs: 0,       // ms of trailing 'still' band before in_vehicle
  stepReportLatencyMs: 10000,  // Android step-detector FIFO latency (0 = real-time)

  // ── iOS power layer ────────────────────────────────────────────────────
  powerMode: 'liveUpdates',    // 'liveUpdates' (iOS 17+, default) | 'arbiter'

  // ── Lifecycle ─────────────────────────────────────────────────────────
  wakeOnTerminate: false,      // true = survive swipe-kill and revive tracking

  // ── Native RTDB sink (optional, for Firebase-backed apps) ─────────────
  nativeSync: false,           // true = native layer writes events to RTDB
  nativeSyncRootPath: '/tests/locations',

  // ── License (required for release builds) ─────────────────────────────
  licenseKey: process.env.EXPO_PUBLIC_MOBG_LICENSE_KEY,
});
```

### `desiredAccuracy`

| Value | Android | iOS |
|-------|---------|-----|
| `'high'` | HIGH_ACCURACY priority @ 1 s | Best accuracy, dense cadence |
| `'high@5s'` | HIGH_ACCURACY priority @ 5 s | Same as `'high'` (cadence is not a CL concept) |
| `'balanced'` | BALANCED_POWER @ 5 s — WiFi/cell fused, no GNSS chip | WiFi/cell |

`'balanced'` never lights the GNSS chip and suits dense urban areas. In
WiFi-sparse terrain (rural, motorways) use `'high@5s'` — `'balanced'` can
produce Doppler-free fixes that confuse the classifier.

### `stopTimeout`

Seconds of undetected motion before the state machine transitions to stationary
and pauses active GPS. Note: the field is **seconds** here — some other
libraries use minutes for the same concept.

### `labelMode`

| Value | Classifier | Transitions | GPS needed |
|-------|-----------|-------------|-----------|
| `'residual'` | Doppler speed + covering-ground sustain | ~5–15 s after motion changes | Yes (speed from GPS) |
| `'steps'` | Step recency: step present → walking; quiet window elapsed → in_vehicle | ~instant | No |

`'steps'` is ideal for fleet/driver apps where the meaningful signal is *active
walking* (between stops). The trade-off is that stationary-on-foot reads
`in_vehicle` after the quiet window. Pair with `stepReportLatencyMs: 0` for
instant transitions; the default 10 s batch causes per-batch flicker on a
continuous walk.

### `deepIdleAfter` / `deepIdlePollInterval` (Android)

After `deepIdleAfter` minutes of undisturbed park, the 5-minute stationary poll
drops to the rare `deepIdlePollInterval`-minute safety poll. This eliminates
continuous overnight polling — a phone parked all night consumes a fraction of
the battery compared to a steady 5-min poll floor.

The only downside is that a *silent* rolling departure (car rolling away with no
person walking up to it) is detected at worst one poll interval late. Walk-up
and pickup departures are still caught immediately by the motion sensors regardless.

### `tightPollWindowMinutes` (Android)

For the first `tightPollWindowMinutes` minutes after a stop, the poll runs at
60 seconds and departure requires 2 fixes ≥ 150 m with a relaxed accuracy gate
(cold Doze-poll fixes can read poor accuracy but are real). After the window,
the poll relaxes to 5 minutes and the strict departure rule resumes (1 fix ≥ 120 m,
accuracy ≤ 30 m).

Size this to the longest errand you want to catch under tight polling. Default: 45.

### `powerMode` (iOS)

| Value | Wake mechanism | Measured latency |
|-------|---------------|-----------------|
| `'liveUpdates'` (default) | Apple's CLLocationUpdate stationarity engine — motion-triggered delivery resume | 4–22 s / 10–77 m (field runs F4) |
| `'arbiter'` | Our stillness arbiter + CLMonitor region-exit + SLC | ~60–90 s (geometric) |

Region exit and Significant Location Change stay armed as backstops in **both**
arms, so every drive yields a which-fired-first row. Switch arms with
`stop()` → `configure({ powerMode })` → `start()`. iOS < 17 falls back to
`'arbiter'` automatically.

### `wakeOnTerminate`

- `false` (default): swipe-kill stops tracking. Clean teardown — no background
  revival until the user reopens the app.
- `true`: tracking survives user termination. iOS uses region-exit/SLC/visit
  relaunch; Android uses `START_STICKY` + broadcast receivers.
  OS deaths (jetsam, crashes, reboots) revive tracking in both modes.

### `nativeSync` + `nativeSyncRootPath`

When `true`, the native layer (foreground service on Android; `TrackingRuntime`
on iOS) writes every location, motion, wake, and diagnostic event directly to
Firebase RTDB — without a live JS context. This means events land even after a
swipe-kill, JS crash, or an OS-initiated background relaunch that never warms
up the JS layer.

Requires a default `FirebaseApp` in the host app (add `google-services.json`
/ `GoogleService-Info.plist` and call `configure()` in the native layer). The
module reuses the anonymous-auth UID created by the JS side as `driverId`.

**Single-writer rule:** when `nativeSync` is on, disable JS-side sink writes
to avoid duplicating events under two session keys.

---

## API

### `configure(config: Config): Promise<void>`

Stash the configuration. Safe to call at any time, including before permissions
are granted. Changes take effect at the next `start()` call (or immediately for
fields that don't require a restart, like `notificationBody`).

### `requestPermissions(options): Promise<PermissionStatus>`

Request the OS permissions needed for background tracking:

```ts
await requestPermissions({
  background: true,   // ACCESS_BACKGROUND_LOCATION / Always authorization
  activity: true,     // ACTIVITY_RECOGNITION (Android 10+)
});
```

### `getPermissions(): Promise<PermissionStatus>`

Read current permission state without prompting.

```ts
const perms = await getPermissions();
// { foreground: boolean, background: boolean, activity: boolean, notifications: boolean }
```

### `start(): Promise<void>`

Start tracking. Reads the stashed config and latches it for the run. Rejects
with `ERR_LICENSE` on a release build without a valid key.

### `stop(): Promise<void>`

Stop tracking. Tears down the foreground service / background task and clears
active registrations.

### `getCurrentPosition(): Promise<LocationEvent>`

One-shot current location (no continuous tracking required).

### `getPowerStats(): Promise<PowerStats>`

Read the current battery and power-state snapshot.

### `onLocation(callback): Subscription`

Fires on every location update while moving:

```ts
const sub = onLocation((e: LocationEvent) => {
  // e.latitude, e.longitude, e.accuracy
  // e.speed          — m/s (null if unavailable)
  // e.activity       — 'walking' | 'running' | 'on_bicycle' | 'in_vehicle' | 'still' | 'unknown'
  // e.isMoving       — true while in moving state
  // e.timestamp      — Unix ms
});
```

### `onMotionChange(callback): Subscription`

Fires on stationary ↔ moving state transitions **and** on activity label
promotions (e.g. `still` → `walking` → `in_vehicle`):

```ts
const sub = onMotionChange((e: MotionEvent) => {
  // e.isMoving, e.activity, e.timestamp
});
```

### `onMotionWake(callback): Subscription`

Fires when the stationary engine wakes due to detected motion:

```ts
const sub = onMotionWake((e: MotionWakeEvent) => {
  // e.reason         — 'sig-motion' | 'live-resume' | 'geofence' | 'slc' | …
  // e.displacement   — metres from the park anchor (if available)
});
```

### `onDiagnostic(callback): Subscription`

Fires on internal engine events: polls, geofence arm/disarm, soft-stop vetoes.
Useful for debugging; leave off in production unless you need it.

```ts
const sub = onDiagnostic((e: DiagnosticEvent) => {
  // e.kind: 'poll' | 'geofence' | 'softstop' | 'wake' | …
  // e.accuracy, e.accuracyGated, e.intervalMs, …
});
```

---

## Full example — typical driver app

```tsx
import {
  configure,
  getPermissions,
  requestPermissions,
  start,
  stop,
  onLocation,
  onMotionChange,
  type LocationEvent,
  type MotionEvent,
} from 'mo-bg-location';
import { useEffect, useState } from 'react';

export default function TrackingScreen() {
  const [lastLocation, setLastLocation] = useState<LocationEvent | null>(null);
  const [motion, setMotion] = useState<MotionEvent | null>(null);
  const [isTracking, setIsTracking] = useState(false);

  useEffect(() => {
    // Configure once on mount
    configure({
      desiredAccuracy: 'high@5s',
      distanceFilter: 10,
      stopTimeout: 90,
      labelMode: 'steps',       // GPS-free, instant activity labels
      stepReportLatencyMs: 0,   // real-time steps for instant transitions
      deepIdleAfter: 90,
      deepIdlePollInterval: 30,
      tightPollWindowMinutes: 45,
      notificationTitle: 'On shift',
      notificationBody: 'Location tracking is active.',
      licenseKey: process.env.EXPO_PUBLIC_MOBG_LICENSE_KEY,
    }).catch(console.error);

    const locSub  = onLocation((e) => setLastLocation(e));
    const motSub  = onMotionChange((e) => setMotion(e));

    return () => { locSub.remove(); motSub.remove(); };
  }, []);

  const handleStart = async () => {
    const perms = await getPermissions();
    if (!perms.background) {
      await requestPermissions({ background: true, activity: true });
    }
    await start();
    setIsTracking(true);
  };

  const handleStop = async () => {
    await stop();
    setIsTracking(false);
  };

  return (
    // … your UI
  );
}
```

---

## Permissions

### Android

The config plugin adds these automatically via prebuild:

| Permission | Purpose |
|------------|---------|
| `ACCESS_FINE_LOCATION` | Foreground GPS |
| `ACCESS_BACKGROUND_LOCATION` | Background GPS (Android 10+) |
| `ACTIVITY_RECOGNITION` | Step detector + AR (Android 10+) |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` | Location foreground service |
| `RECEIVE_BOOT_COMPLETED` | Revive tracking after reboot |

### iOS

Background mode `location` and `motion` entitlements are added by the config
plugin. The app must supply `NSLocationWhenInUseUsageDescription`,
`NSLocationAlwaysAndWhenInUseUsageDescription`, and
`NSMotionUsageDescription` strings in `Info.plist` (set via Expo's
`infoPlist` in `app.json`).

---

## Troubleshooting

| Symptom | Likely cause |
|---------|-------------|
| `start()` never resolves | Missing foreground location permission — call `requestPermissions` first |
| Labels stuck on `unknown` | `ACTIVITY_RECOGNITION` not granted (Android) or motion permission denied (iOS) |
| No updates after swipe-kill | `wakeOnTerminate` is `false` (default) — set `true` if you need tracking to survive a kill |
| iOS wake latency > 30 s | iOS < 17 falls back to `'arbiter'`; on iOS 17+ confirm `powerMode: 'liveUpdates'` |
| Overnight battery drain | `deepIdleAfter` not set or set to 0 — set to `90` (minutes) |
| `ERR_LICENSE` on start | Release build with no key; see Licensing |

---

## Licensing

**Development is free.** The SDK works fully in debug builds, the iOS simulator,
and dev-signed device builds — no key needed.

**Release builds require a license key** bound to your app's `packageName` /
bundle ID (one key covers both platforms):

```ts
await configure({
  licenseKey: process.env.EXPO_PUBLIC_MOBG_LICENSE_KEY,
  // … rest of config
});
```

The key is a signed public statement — safe to commit and ship in your JS
bundle. Contact <info@aalillou.be> to obtain one.

A release build with a missing, expired, or wrong-app key **rejects `start()`
loudly** with code `ERR_LICENSE` so you catch it in your first release-build
smoke test. `configure()` also logs a one-line verdict on every launch
(`license: development mode — no key required` / `license: valid for <appId>` /
the failure reason).

To exercise the release gate on a dev-signed iOS build (free-team codesign),
add `licenseEnforceRelease: true` to `configure()`. This flag can only *add*
enforcement, never bypass it — leave it off in production.

---

## License

Proprietary — see [LICENSE](./LICENSE). The engine binaries contain no
third-party code; required components (Expo, React Native, Firebase, Google
Play services) are resolved by your app and licensed separately — see
[THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.md).
