#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// "Legacy" storage with a completion-handler API that runs on a GCD queue.
///
/// Swift automatically imports these methods as `async`:
///   - `loadValue(forKey:) async -> String?`
///   - `saveValue(_:forKey:) async`
/// The completion runs on a background queue; the `await` in Swift resumes on the
/// caller's executor (for example, the MainActor).
///
/// NS_SWIFT_SENDABLE: the class is thread-safe (every access goes through the serial queue),
/// so it can cross concurrency boundaries in Swift.
NS_SWIFT_SENDABLE
@interface CLALegacyKeyValueStore : NSObject

@property (class, nonatomic, readonly) CLALegacyKeyValueStore *sharedStore NS_SWIFT_NAME(shared);

- (instancetype)initWithSuiteName:(nullable NSString *)suiteName NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

- (void)loadValueForKey:(NSString *)key completion:(void (^)(NSString *_Nullable value))completion;
- (void)saveValue:(NSString *)value forKey:(NSString *)key completion:(void (^_Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
