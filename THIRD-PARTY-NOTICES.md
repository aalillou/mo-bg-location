# Third-party notices

## The engine binaries contain no third-party code

The prebuilt native engine binaries shipped in this package — `android/libs/mobg-location-release.aar`
and `ios/MoBGLocationEngine.xcframework` — contain **only** code owned by the Licensor.
No third-party library is compiled into, statically linked into, or otherwise
redistributed inside them.

This is enforced at build time: the Android AAR is verified to bundle no
Firebase/Google Play classes, and the iOS framework is built as a static library and
verified to bundle no Firebase/Google object files.

## Required, but not redistributed

The Software depends on the components below at build and run time. They are **not**
redistributed by this package — your application resolves them itself, from npm,
Maven, and CocoaPods, and your use of them is governed by their own licenses.

| Component | Obtained from | License |
| --- | --- | --- |
| Expo / `expo-modules-core` | npm, CocoaPods, Maven | MIT |
| React Native | npm | MIT |
| Firebase (Android/iOS SDKs) | Maven, CocoaPods | Apache-2.0 |
| Google Play services — Location | Maven | Android Software Development Kit License |

## Project scaffolding

This project was originally generated with Expo's `create-expo-module` template.
Portions of the repository's build tooling derive from that template, which is
distributed under the MIT License:

```
The MIT License (MIT)

Copyright (c) 2015-present 650 Industries, Inc. (aka Expo)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The mo-bg-location SDK itself is proprietary — see [LICENSE](./LICENSE).
