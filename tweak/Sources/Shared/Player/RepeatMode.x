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
static NSString *sg_track, *sg_context;
static NSString *sg_requestedTrack, *sg_requestedContext;
static SGRepeatBits sg_requested, sg_requestedMask;
static _Thread_local BOOL sg_restoring;

static BOOL sameURI(NSString *a, NSString *b) {
    return a == b || [a isEqualToString:b];
}

static void clearRequest(void) {
    sg_requested = sg_requestedMask = 0;
    sg_requestedTrack = sg_requestedContext = nil;
}

static void rememberRequest(id player, NSNumber *context, NSNumber *track) {
    if (sg_restoring || !SGFlag(SGKeyRememberRepeatMode, NO) || (!context && !track)) return;
    dispatch_block_t note = ^{
        if (player != SGPlayer() || !SGFlag(SGKeyRememberRepeatMode, NO)) return;
        SPTPlayerState *state = SGPlayerState();
        NSString *trackURI = SGURIString(state.track.URI), *contextURI = SGURIString(state.contextURI);
        if (!sameURI(trackURI, sg_requestedTrack) || !sameURI(contextURI, sg_requestedContext)) clearRequest();
        sg_requestedTrack = trackURI;
        sg_requestedContext = contextURI;
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
    if (!enabled) clearRequest();
    NSString *track = SGURIString(state.track.URI), *context = SGURIString(state.contextURI);
    if (!track.length || ([state respondsToSelector:@selector(isLoading)] && state.isLoading)) return;
    if (sg_requestedMask) {
        BOOL samePlayback = !sg_requestedTrack || (sameURI(track, sg_requestedTrack) && sameURI(context, sg_requestedContext));
        if (!samePlayback) clearRequest();
        else if ((bits & sg_requestedMask) == sg_requested) {
            clearRequest();
            SGSetInt(kLastRepeatMode, bits);
        }
    }

    if (sameURI(track, sg_track) && sameURI(context, sg_context)) return;
    sg_track = track;
    sg_context = context;
    if (!enabled || sg_requestedMask) return;
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
