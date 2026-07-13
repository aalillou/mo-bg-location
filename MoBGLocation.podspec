# PUBLIC (binary) podspec — generated into the published package by
# internal/module_scripts/pack-public.js. Do not edit the generated copy; edit
# this template. See docs/mo-bg-as-commercial-SDK.md (Locked Decisions, #2).
#
# Contrast with the PRIVATE source podspec (../../MoBGLocation.podspec), which
# compiles ios/**/* + swift-core/Sources/**. This one ships the ENGINE as a
# prebuilt xcframework and keeps only the thin Expo SHIM as source.
Pod::Spec.new do |s|
  s.name           = 'MoBGLocation'
  s.version        = '0.1.0'
  s.summary        = 'Background location tracking with a self-computed activity classifier'
  s.description    = 'Background location engine with a self-computed activity classifier and a battery-aware motion state machine (binary distribution).'
  s.author         = { 'Aalillou' => 'info@aalillou.be' }
  s.homepage       = 'https://github.com/aalillou/mo-bg-location'
  # Proprietary — free for development, license key required for release builds.
  s.license        = { :type => 'Commercial', :file => 'LICENSE' }
  s.platforms      = {
    :ios => '16.4'
  }
  s.source         = { git: '' }
  s.static_framework = true

  # Dependencies are NOT baked into the xcframework — they stay pod
  # dependencies so the host app's CocoaPods resolution provides them (the iOS
  # analogue of the Android AAR's re-declared transitive deps).
  s.dependency 'ExpoModulesCore'
  s.dependency 'FirebaseDatabase'
  s.dependency 'FirebaseAuth'
  s.frameworks = 'CoreLocation', 'CoreMotion'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # The engine is a SEPARATE module here (it ships prebuilt), so the shim must
    # `import MoBGLocationEngine`. That import is #if MOBG_BINARY-guarded in the
    # shared shim source, because the SOURCE podspec compiles engine + shim into
    # one module where the import would not resolve. This flag is what selects
    # the binary arm.
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) MOBG_BINARY',
  }

  # SHIM (source): the thin Expo Module {} surface + the AppDelegate subscriber.
  # They recompile against the HOST APP's ExpoModulesCore, so they must stay
  # source (decision #2) — never bury them in the binary.
  s.source_files = 'ios/MoBGLocationModule.swift', 'ios/MoBGLocationAppDelegateSubscriber.swift'

  # ENGINE (binary): the valuable CoreLocation/CoreMotion controllers, motion
  # state machine, classifier, RTDB sink, power ledger — Foundation-only public
  # API, Expo-agnostic.
  #
  # NOTE the module name: it must NOT be `MoBGLocation`, because this pod is
  # itself named MoBGLocation and compiles the shim into a module of that name —
  # a vendored framework with the same name collides. Hence MoBGLocationEngine.
  s.vendored_frameworks = 'ios/MoBGLocationEngine.xcframework'
end
