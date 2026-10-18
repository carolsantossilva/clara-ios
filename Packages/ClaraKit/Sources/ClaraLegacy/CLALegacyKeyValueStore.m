#import "CLALegacyKeyValueStore.h"

@interface CLALegacyKeyValueStore ()
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) NSUserDefaults *defaults;
@end

@implementation CLALegacyKeyValueStore

+ (CLALegacyKeyValueStore *)sharedStore {
    static CLALegacyKeyValueStore *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[CLALegacyKeyValueStore alloc] initWithSuiteName:nil];
    });
    return shared;
}

- (instancetype)init {
    return [self initWithSuiteName:nil];
}

- (instancetype)initWithSuiteName:(NSString *)suiteName {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("app.clara.legacy-store", DISPATCH_QUEUE_SERIAL);
        _defaults = suiteName ? [[NSUserDefaults alloc] initWithSuiteName:suiteName] : NSUserDefaults.standardUserDefaults;
    }
    return self;
}

- (void)loadValueForKey:(NSString *)key completion:(void (^)(NSString *_Nullable))completion {
    dispatch_async(self.queue, ^{
        NSString *value = [self.defaults stringForKey:key];
        // Regra de ouro ao virar `async` no Swift: o completion é chamado exatamente uma vez.
        completion(value);
    });
}

- (void)saveValue:(NSString *)value forKey:(NSString *)key completion:(void (^)(void))completion {
    dispatch_async(self.queue, ^{
        [self.defaults setObject:value forKey:key];
        if (completion) {
            completion();
        }
    });
}

@end
