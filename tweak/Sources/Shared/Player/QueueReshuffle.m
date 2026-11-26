#import "Core/SGFlagForce.h"
#import "Core/SGPrefs.h"
#import "QueueHelpers.h"

static NSString *const kReshuffleFlag = @"ios-feature-queue.is_reshuffle_enabled";

__attribute__((constructor)) static void registerQueueReshuffle(void) {
    BOOL on = SGFlag(SGKeyQueueReshuffle, NO);
    SGRegisterFlagForcer(YES, ^id(NSString *key) {
        return on && [key isEqualToString:kReshuffleFlag] ? @YES : nil;
    }, ^id(NSString *key) {
        return [key isEqualToString:kReshuffleFlag] && SGFlag(SGKeyQueueReshuffle, NO) ? @YES : nil;
    });
}
