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

- **Delivery that survives a killed JS context — into *your* database shape.**
  The optional native RTDB sink writes location, motion, and diagnostic events
  from the native foreground service (Android) or `TrackingRuntime` (iOS) with
  no JS alive — and an [output template](#nativesynctemplate--writing-your-own-rtdb-shape)
  lets you declare the exact paths and value tree it writes, so the events land
  in the schema your app already reads instead of one imposed by the SDK.

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

### iOS: apps that don't already use Firebase

The SDK's optional native Firebase sink links the Firebase iOS pods. If your
app does **not** already depend on React Native Firebase, `pod install` fails
on Firebase's modular headers unless CocoaPods builds frameworks statically.
Add [`expo-build-properties`](https://docs.expo.dev/versions/latest/sdk/build-properties/)
to your `app.json`:

```jsonc
"plugins": [
  ["expo-build-properties", { "ios": { "useFrameworks": "static" } }]
]
```

(Apps already on `@react-native-firebase/*` have this set — its install docs
require the same flag.)

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
} from '@aalillou/mo-bg-location';

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
  nativeSyncRootPath: '/tests/locations',   // built-in schema only
  nativeSyncTemplate: undefined,            // your own paths + value tree
  nativeSyncParams:   undefined,            // static {param.*} values

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
/ `GoogleService-Info.plist` and call `configure()` in the native layer).
Without a template (below) the sink writes the SDK's **built-in schema** under
`nativeSyncRootPath`, keyed by the anonymous-auth UID the JS side creates.

**Single-writer rule:** when `nativeSync` is on, disable JS-side sink writes
to avoid duplicating events under two session keys.

### `nativeSyncTemplate` — writing your own RTDB shape

The built-in schema is almost certainly not the tree your app reads. A
**template** tells the native sink exactly which paths to write and what value
tree to put there — so you keep everything that makes the native sink worth
having (delivery that survives a dead JS context, offline queueing, background
writes) while the data lands in *your* shape.

`nativeSync: true` is still the master switch: the template says *what* to
write, that flag says *whether* the native layer writes at all. When a template
is set, `nativeSyncRootPath` is ignored — template paths are absolute.

```ts
await configure({
  // … tracking config …

  nativeSync: true,
  nativeSyncParams: {                 // static identity → {param.*}
    sessionKey: 'shift-42',
    nodeKey: '12_Doe',
    driverId: 12,
  },
  nativeSyncTemplate: {
    targets: [
      {
        trigger: 'location',
        path: 'fleet/locations/{param.sessionKey}/{param.nodeKey}',
        // A map does not need 1 Hz. Either gate opens the write: a slow crawl
        // still reports every 5 s, a fast drive reports every 25 m.
        throttle: { minIntervalMs: 5000, minDistanceM: 25 },
        // Presence: the server deletes this node when the device goes offline.
        onDisconnectRemove: true,
        value: {
          g: '{geohash}',             // GeoFire-compatible query key
          l: '{latlng}',              // [lat, lng]
          data: {
            driverId: '{param.driverId}',
            activity: '{activity}',   // still | on_foot | in_vehicle | …
            updated_at: '{isoTime}',
            battery: { level: '{battery.level}', is_charging: '{battery.isCharging}' },
            $extras: true,            // merge in whatever setSyncExtras() holds
          },
        },
      },
    ],
  },
});
```

**How values resolve**

- A string that is **exactly one placeholder** becomes that native type:
  `"{lat}"` writes a number, `"{latlng}"` writes an array, `"{isMoving}"` a boolean.
- A placeholder **inside a longer string** is interpolated as text
  (`"driver {param.driverId}"`). Fractional numbers (`{lat}`, `{speed}`) may not
  be embedded this way — use them as exact-one placeholders.
- A placeholder that **resolves to nothing drops its key** rather than writing `null`.

**Placeholders**

| Scope | Available |
|-------|-----------|
| every trigger | `{ts}` `{isoTime}` `{timeLocal}` `{timeKey}` `{sessionId}` `{platform}` `{battery.level}` (0..1) `{battery.isCharging}` `{param.*}` `{extra.*}` |
| `location` | `{lat}` `{lng}` `{latlng}` `{geohash}` `{accuracy}` `{speed}` `{activity}` `{isMoving}` |
| `motion` | `{activity}` `{isMoving}` |
| `wake` | wake reason / displacement fields |
| `diagnostic` | `{kind}`, plus `"$event": true` to spread the raw event |

**Targets**

| Field | Meaning |
|-------|---------|
| `trigger` | `'location'` \| `'motion'` \| `'wake'` \| `'diagnostic'` |
| `path` | Absolute path from the database root |
| `mode` | `'set'` (default, overwrite) or `'update'` (merge into the node) |
| `throttle` | `location` only. `{ minIntervalMs, minDistanceM }` — with both, **either** gate opens the write |
| `onDisconnectRemove` | Delete the node when the device's connection drops. Static paths only; re-armed on every reconnect, and **not** cancelled by `stop()` — a killed device must not stay on your map forever |
| `value` | The JSON tree to write |

Up to 8 targets. `"$extras": true` inside an object merges in the
[`setSyncExtras`](#setsyncextrasextras-promisevoid) bag; explicit keys win.

**Paths are validated, not trusted.** Only placeholders guaranteed to produce a
legal RTDB key may appear in `path` (`{param.*}`, `{sessionId}`, `{timeKey}`,
`{activity}`, `{geohash}`, `{ts}`, `{platform}`, `{isMoving}`, `{kind}`). A
`{lat}` in a path would turn `51.2` into two nested nodes, so `configure()`
rejects it with **`ERR_SYNC_TEMPLATE`** — as it does for unknown placeholders,
illegal path characters, and any `{param.*}` you forgot to supply.

**Don't run two writers.** If your JS also writes these paths while `nativeSync`
is on, you have two writers racing on the same nodes. Pick one.

### Securing template writes

The template writes through **your app's existing Firebase login** — the SDK
never signs in and never signs out, it inherits whatever user your app already
authenticated (`FirebaseAuth.getInstance().currentUser`), including that user's
`auth.uid` and any custom claims. Your **RTDB security rules** are the
enforcement; the `{param.*}` values in a path are only a *claim* of identity, and
your rules are what verify the logged-in user is allowed to write there.

Secure it with ordinary rules against that session plus the path — coarsest to
tightest:

```jsonc
// 1. Any logged-in user
"fleet": { "locations": { ".write": "auth != null" } }

// 2. Tenant-scoped — path carries {param.tenant}, rule checks a claim
"$tenant": { "locations": { ".write": "auth.token.tenant === $tenant" } }

// 3. Per-driver, securing a HUMAN key via a custom claim
"fleet": { "locations": { "$session": { "$driverKey": {
  ".write": "auth.token.driverKey === $driverKey"
} } } }
```

Pattern 3 is how you secure a path keyed by something like `12_Doe` rather than
the uid: your backend sets a `driverKey` (or `tenant`, or `role`) **custom claim**
when the driver logs in, you put `{param.nodeKey}` in the path, and the rule
cross-checks the path key against the claim. So: **params supply the claimed
identity, the authenticated session supplies the trusted identity, and your rule
asserts they match.**

**The revival window.** The whole point of `nativeSync` is writing when no JS is
alive (swipe-kill, crash, OS background relaunch), so your app's normal sign-in
code hasn't run. Anonymous and email/password sessions **persist to disk** and a
revived native process auto-restores and refreshes them, so `auth.uid` and
token-baked claims survive a kill — rules keyed on them still pass. The exception
is auth that only *your backend/JS* can mint (a custom-token flow): a revived
JS-less process may write with a stale or absent token until your app re-auths,
and those writes are rejected in the gap (logged once, then quiet). Prefer an auth
whose session persists across process death, or accept that the first few
post-revival writes may be refused until the next launch.

---

## API

### `configure(config: Config): Promise<void>`

Stash the configuration. Safe to call at any time, including before permissions
are granted. Changes take effect at the next `start()` call (or immediately for
fields that don't require a restart, like `notificationBody`).

Rejects with `ERR_SYNC_TEMPLATE` if `nativeSyncTemplate` is invalid.

### `requestPermissions(options): Promise<PermissionStatus>`

Request the OS permissions needed for background tracking:

```ts
await requestPermissions({
  background: true,   // ACCESS_BACKGROUND_LOCATION / Always authorization
  activity: true,     // ACTIVITY_RECOGNITION (Android 10+) / Motion & Fitness (iOS)
});
```

The stages run as a ladder, identical on both platforms: **foreground location
is always requested first**; the background upgrade (Android
`ACCESS_BACKGROUND_LOCATION` / iOS Always) runs only when `background: true`
and foreground was granted; the motion stage (Android `ACTIVITY_RECOGNITION` /
iOS Motion & Fitness) runs only when `activity: true` and foreground was
granted. The resolved `PermissionStatus` merges the outcome of every stage.
One combined call is therefore all a typical driver app needs.

### `getPermissions(): Promise<PermissionStatus>`

Read current permission state without prompting.

```ts
const perms = await getPermissions();
// { foreground: boolean, background: boolean, activity: boolean,
//   notifications: boolean, precise: boolean }
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

### `setSyncExtras(extras): Promise<void>`

Set the mutable values your `nativeSyncTemplate` writes as `{extra.*}` (or
spreads with `"$extras": true`) — the things that change *during* a shift: a
booking id, the parcels currently loaded, a status flag. Identity that doesn't
change belongs in `nativeSyncParams` instead.

**Whole-bag replace, not a merge** — pass everything you want written:

```ts
await setSyncExtras({ charged: ['pkg-1', 'pkg-2'], bookingId: 42 });
await setSyncExtras({ charged: [] });   // bookingId is now GONE, not kept
```

The bag is persisted natively and **survives the JS context dying**, which is
the point: a process revived without JS keeps writing rows that still carry your
shift state. It also deliberately survives `stop()` — the next `start()` renders
with the last bag you set until you replace it. (Dropping it would mean a revived
process writes rows *missing* your shift state, which is worse than a stale one;
you always get the chance to overwrite.)

Rejects with `ERR_SYNC_EXTRAS` if a key is not a legal RTDB key, or the bag
exceeds 16 KB.

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
  setSyncExtras,
  start,
  stop,
  onLocation,
  onMotionChange,
  type LocationEvent,
  type MotionEvent,
} from '@aalillou/mo-bg-location';
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

      // Write straight into the tree this app already reads — and keep writing
      // it even if the OS kills the JS context mid-shift.
      nativeSync: true,
      nativeSyncParams: { sessionKey: shiftId, nodeKey: driverKey, driverId },
      nativeSyncTemplate: {
        targets: [{
          trigger: 'location',
          path: 'fleet/locations/{param.sessionKey}/{param.nodeKey}',
          throttle: { minIntervalMs: 5000, minDistanceM: 25 },
          onDisconnectRemove: true,
          value: {
            g: '{geohash}',
            l: '{latlng}',
            data: {
              driverId: '{param.driverId}',
              activity: '{activity}',
              updated_at: '{isoTime}',
              $extras: true,        // ← whatever setSyncExtras() holds
            },
          },
        }],
      },

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

  // Shift state that must keep being written even if the app is killed.
  const handleLoadParcel = async (parcels: string[]) => {
    await setSyncExtras({ charged: parcels });
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
| `ERR_SYNC_TEMPLATE` on configure | Invalid `nativeSyncTemplate` — the message names the offending target and placeholder |
| Template tree stays empty | Writes rejected by your security rules (the SDK writes as your app's existing auth — check the device log for the one-time rejection), or `nativeSync` is not `true` |
| `{extra.*}` values missing from writes | `setSyncExtras` is a whole-bag replace — a later call without a key removes it |

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
