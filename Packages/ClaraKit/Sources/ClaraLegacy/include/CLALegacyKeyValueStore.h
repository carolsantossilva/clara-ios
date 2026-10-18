#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Armazenamento "legado" com API de completion handler executada numa fila GCD.
///
/// O Swift importa estes métodos automaticamente como `async`:
///   - `loadValue(forKey:) async -> String?`
///   - `saveValue(_:forKey:) async`
/// O completion roda numa fila de background; o `await` no Swift retoma no
/// executor de quem chamou (por exemplo, o MainActor).
///
/// NS_SWIFT_SENDABLE: a classe é thread-safe (todo acesso passa pela fila serial),
/// então pode atravessar fronteiras de concorrência no Swift.
NS_SWIFT_SENDABLE
@interface CLALegacyKeyValueStore : NSObject

@property (class, nonatomic, readonly) CLALegacyKeyValueStore *sharedStore NS_SWIFT_NAME(shared);

- (instancetype)initWithSuiteName:(nullable NSString *)suiteName NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

- (void)loadValueForKey:(NSString *)key completion:(void (^)(NSString *_Nullable value))completion;
- (void)saveValue:(NSString *)value forKey:(NSString *)key completion:(void (^_Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
