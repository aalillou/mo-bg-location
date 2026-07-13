#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift cannot catch NSExceptions — this is the one place the module needs to
/// (`FIRDatabase.persistenceEnabled` raises `FIRDatabaseAlreadyInUse` when set
/// after the first reference is created; see `NativeRtdbSink.attach`). The
/// Kotlin sink's `try/catch (Throwable)` equivalent.
@interface MoBGExceptionCatcher : NSObject

/// Runs `block`; returns the NSException it raised, or nil on clean execution.
+ (NSException *_Nullable)catchExceptionIn:(void (NS_NOESCAPE ^)(void))block;

@end

NS_ASSUME_NONNULL_END
