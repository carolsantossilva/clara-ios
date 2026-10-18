#import "CLADurationFormatter.h"

@implementation CLADurationFormatter

+ (NSString *)clockStringFromSeconds:(NSInteger)seconds {
    NSInteger safe = MAX(0, seconds);
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(safe / 60), (long)(safe % 60)];
}

+ (NSString *)spokenStringFromSeconds:(NSInteger)seconds {
    NSInteger safe = MAX(0, seconds);
    NSInteger minutes = safe / 60;
    NSInteger remainder = safe % 60;

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (minutes > 0) {
        [parts addObject:[NSString stringWithFormat:@"%ld %@", (long)minutes, minutes == 1 ? @"minuto" : @"minutos"]];
    }
    if (remainder > 0 || minutes == 0) {
        [parts addObject:[NSString stringWithFormat:@"%ld %@", (long)remainder, remainder == 1 ? @"segundo" : @"segundos"]];
    }
    return [parts componentsJoinedByString:@" e "];
}

@end
