#import "QueueHelpers.h"
#import <math.h>

NSString *SGQueueDurationText(SPTPlayerState *state) {
    NSArray *future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    if (![future isKindOfClass:NSArray.class]) return @"Queue duration unavailable";
    if (!future.count) return @"Queue is empty";

    double milliseconds = 0;
    NSUInteger known = 0;
    Class trackClass = NSClassFromString(@"SPTPlayerTrack");
    for (id track in future) {
        if (![track isKindOfClass:trackClass] || ![track respondsToSelector:@selector(metadata)]) continue;
        NSDictionary *metadata = ((SPTPlayerTrack *)track).metadata;
        id value = [metadata isKindOfClass:NSDictionary.class] ? metadata[@"duration"] : nil;
        if (![value isKindOfClass:NSNumber.class] && ![value isKindOfClass:NSString.class]) continue;
        double duration = [value doubleValue];
        if (!isfinite(duration) || duration <= 0) continue;
        milliseconds += duration;
        known++;
    }
    if (!known || !isfinite(milliseconds)) return @"Queue duration unavailable";
    if (known < future.count) {
        if (milliseconds < 60000) return @"Total duration unavailable";
        return [NSString stringWithFormat:@"At least %.0f min in queue", floor(milliseconds / 60000)];
    }
    if (milliseconds < 60000) return @"Less than 1 min in queue";
    return [NSString stringWithFormat:@"About %.0f min in queue", round(milliseconds / 60000)];
}
