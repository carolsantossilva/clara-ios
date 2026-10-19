#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A "legacy" Objective-C formatter, called from Swift (TodayFeature).
/// Stands in for the old code that lives alongside new code in large apps.
@interface CLADurationFormatter : NSObject

/// "14:05"
+ (NSString *)clockStringFromSeconds:(NSInteger)seconds NS_SWIFT_NAME(clockString(seconds:));

/// "14 minutos e 5 segundos" (14 minutes and 5 seconds), used as the VoiceOver label.
+ (NSString *)spokenStringFromSeconds:(NSInteger)seconds NS_SWIFT_NAME(spokenString(seconds:));

@end

NS_ASSUME_NONNULL_END
