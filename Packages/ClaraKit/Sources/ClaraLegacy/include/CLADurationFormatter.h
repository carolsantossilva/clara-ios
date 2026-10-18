#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Formatador "legado" em Objective-C, chamado a partir do Swift (TodayFeature).
/// Simula o código antigo que convive com o novo em apps grandes.
@interface CLADurationFormatter : NSObject

/// "14:05"
+ (NSString *)clockStringFromSeconds:(NSInteger)seconds NS_SWIFT_NAME(clockString(seconds:));

/// "14 minutos e 5 segundos" — usado como rótulo do VoiceOver.
+ (NSString *)spokenStringFromSeconds:(NSInteger)seconds NS_SWIFT_NAME(spokenString(seconds:));

@end

NS_ASSUME_NONNULL_END
