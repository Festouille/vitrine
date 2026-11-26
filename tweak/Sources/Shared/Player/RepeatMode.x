#import "Core/SGPrefs.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/RepeatMode.h"

@protocol SGRepeatOptionOverrides <NSObject>
@property (nonatomic, readonly) NSNumber *repeatingContext;
@property (nonatomic, readonly) NSNumber *repeatingTrack;
@end

typedef NS_OPTIONS(NSUInteger, SGRepeatBits) {
    SGRepeatContext = 1 << 0,
    SGRepeatTrack = 1 << 1,
};

static NSString *const kLastRepeatMode = @"spotifyglass.rememberRepeatMode.last";
static BOOL sg_launchHandled;
static SGRepeatBits sg_requested, sg_requestedMask;
static _Thread_local BOOL sg_restoring;

static void rememberRequest(id player, NSNumber *context, NSNumber *track) {
    if (sg_restoring || !SGFlag(SGKeyRememberRepeatMode, NO) || (!context && !track)) return;
    dispatch_block_t note = ^{
        if (player != SGPlayer() || !SGFlag(SGKeyRememberRepeatMode, NO)) return;
        sg_launchHandled = YES;
        if (context) {
            sg_requestedMask |= SGRepeatContext;
            sg_requested = (sg_requested & ~SGRepeatContext) | (context.boolValue ? SGRepeatContext : 0);
        }
        if (track) {
            sg_requestedMask |= SGRepeatTrack;
            sg_requested = (sg_requested & ~SGRepeatTrack) | (track.boolValue ? SGRepeatTrack : 0);
        }
    };
    if (NSThread.isMainThread) note();
    else dispatch_async(dispatch_get_main_queue(), note);
}

@interface SGRepeatModeObserver : NSObject <SGPlayerStateObserver>
@end

@implementation SGRepeatModeObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    id<SPTPlayer> player = SGPlayer();
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    if (!player || ![options respondsToSelector:@selector(repeatingContext)] ||
        ![options respondsToSelector:@selector(repeatingTrack)]) return;

    SGRepeatBits bits = (options.repeatingContext ? SGRepeatContext : 0) | (options.repeatingTrack ? SGRepeatTrack : 0);
    BOOL enabled = SGFlag(SGKeyRememberRepeatMode, NO);
    if (!enabled) sg_requested = sg_requestedMask = 0;
    if (sg_requestedMask && (bits & sg_requestedMask) == sg_requested) {
        sg_requested = 0;
        sg_requestedMask = 0;
        SGSetInt(kLastRepeatMode, bits);
    }

    if (sg_launchHandled || !SGURIString(state.track.URI).length ||
        ([state respondsToSelector:@selector(isLoading)] && state.isLoading)) return;
    sg_launchHandled = YES;
    if (!enabled) return;
    NSInteger saved = SGInt(kLastRepeatMode, -1);
    if (saved == bits || saved < 0 || saved > (SGRepeatContext | SGRepeatTrack) ||
        ![player respondsToSelector:@selector(setRepeatingContext:)] ||
        ![player respondsToSelector:@selector(setRepeatingTrack:)]) return;

    sg_restoring = YES;
    @try {
        if ((bits & SGRepeatTrack) && !(saved & SGRepeatTrack)) [player setRepeatingTrack:NO];
        if ((bits ^ saved) & SGRepeatContext) [player setRepeatingContext:(saved & SGRepeatContext) != 0];
        if (!(bits & SGRepeatTrack) && (saved & SGRepeatTrack)) [player setRepeatingTrack:YES];
    } @finally {
        sg_restoring = NO;
    }
}
@end

%hook SPTEsperantoPlayer
- (id)setRepeatingContext:(BOOL)on {
    rememberRequest(self, @(on), nil);
    return %orig;
}

- (id)setRepeatingTrack:(BOOL)on {
    rememberRequest(self, nil, @(on));
    return %orig;
}

- (id)setOptions:(id<SGRepeatOptionOverrides>)options loggingParams:(id)logging {
    if (SGFlag(SGKeyRememberRepeatMode, NO) && [options isKindOfClass:objc_getClass("SPTPlayerOptionOverrides")]) {
        NSNumber *context = [options respondsToSelector:@selector(repeatingContext)] ? options.repeatingContext : nil;
        NSNumber *track = [options respondsToSelector:@selector(repeatingTrack)] ? options.repeatingTrack : nil;
        rememberRequest(self, context, track);
    }
    return %orig;
}
%end

%ctor {
    %init;
    static SGRepeatModeObserver *observer;
    observer = [SGRepeatModeObserver new];
    SGAddPlayerStateObserver(observer);
}
