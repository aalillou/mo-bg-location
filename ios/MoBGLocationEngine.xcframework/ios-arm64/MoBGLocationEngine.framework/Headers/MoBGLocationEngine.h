// Umbrella header for the MoBGLocationEngine framework (the binary engine).
//
// Its job: expose the ObjC exception catcher to the Swift sources in the SAME
// target, via the generated module map. This is exactly what CocoaPods does for
// the source pod today, which is why the engine sources need no changes to be
// built as a framework.
//
// (MoBGExceptionCatcher exists because Swift cannot catch NSException, and
// FIRDatabase raises FIRDatabaseAlreadyInUse when persistence is set too late —
// see ios/NativeRtdbSink.swift.)
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double MoBGLocationEngineVersionNumber;
FOUNDATION_EXPORT const unsigned char MoBGLocationEngineVersionString[];

#import <MoBGLocationEngine/MoBGExceptionCatcher.h>
