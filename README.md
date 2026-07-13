# mo-bg-location

Background geolocation for Expo / React Native with a self-computed activity
classifier and a battery-aware motion state machine. The native engine ships as
prebuilt binaries (Android `.aar`, iOS `.xcframework`); the JavaScript API and
Expo config plugin are open in this package.

> Commercial SDK — the native engine is license-gated. See **Licensing** below.

## Install

```bash
npx expo install mo-bg-location
```

This is an Expo module with a config plugin. In a managed app, run a prebuild
so the plugin can apply the required Android permissions / foreground service
declarations and iOS background modes:

```bash
npx expo prebuild
```

## Supported Expo SDK range

Each release pins the Expo SDK range it is built against (the native binaries
are compiled against a specific `expo-modules-core`). Installing outside the
supported range is not supported.

| mo-bg-location | Expo SDK |
|----------------|----------|
| (set per release) | (set per release) |

## Usage

```ts
import * as MoBGLocation from 'mo-bg-location';

await MoBGLocation.configure({
  desiredAccuracy: 'balanced',
  stopTimeout: 5,
});

await MoBGLocation.requestPermissions({ background: true, activity: true });
await MoBGLocation.start();

const sub = MoBGLocation.onLocation((location) => {
  // { latitude, longitude, activity, isMoving, ... }
});

MoBGLocation.onMotionChange((event) => {
  // { isMoving, activity, timestamp }
});

// later
sub.remove();
await MoBGLocation.stop();
```

## Licensing

**Development is free.** The SDK is fully functional in debug builds, the iOS
simulator, and dev-signed device builds — no license key required. Try before you
buy.

**Release builds require a license key**, bound to your app's Android package name
and iOS bundle identifier (one key covers both platforms). Configure it at init:

```ts
await MoBGLocation.configure({
  licenseKey: process.env.EXPO_PUBLIC_MOBG_LICENSE_KEY,
  desiredAccuracy: 'balanced',
});
```

The key is a signed *public* statement, not a secret — it is safe to commit and to
ship in your JS bundle. Contact <info@aalillou.be> to obtain one.

### What you'll see without a valid key

A release build with a missing, expired, tampered, or wrong-app key **refuses to
start tracking** — `start()` rejects loudly so you catch it in your first
release-build smoke test rather than shipping an app that silently doesn't track:

- **Android** — the promise rejects with code `ERR_LICENSE`; the message carries
  the reason and the observed package name.
- **iOS** — `start()` throws a license error carrying the same reason.

Typical reasons: `license key required for release builds of <appId>`,
`key is bound to <other.app>`, `signature invalid`, `license expired`.

`configure()` also logs a one-line verdict on every launch
(`license: development mode — no key required` / `license: valid for <appId>` /
the failure reason), so you can confirm the state from the device log.

### Testing the release path during development

Release enforcement only bites a release build, so on a dev-signed build the gate
passes freely. To exercise the release license path on your dev rig (for example,
an iOS free-team device build, which is always dev-signed), set the **test-only**
override — it can only *add* enforcement, never bypass it:

```ts
await MoBGLocation.configure({
  licenseKey: process.env.EXPO_PUBLIC_MOBG_LICENSE_KEY,
  licenseEnforceRelease: true, // treat this build as release for licensing
});
```

Leave it off in production — release builds enforce automatically.

## License

Proprietary — see [LICENSE](./LICENSE). The engine binaries contain no third-party
code; required components (Expo, React Native, Firebase, Google Play services) are
resolved by your app and licensed separately — see
[THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.md).
