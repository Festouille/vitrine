#import "ABLoop.h"
#import "Core/SGPrefs.h"
#import "PlayerState.h"

static const double kMinimumLoop = 1.0;

@interface SGABLoop : NSObject <SGPlayerStateObserver>
@property (nonatomic, copy) NSString *uri;
@property (nonatomic) double start;
@property (nonatomic) double end;
@property (nonatomic) BOOL seeking;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation SGABLoop

- (void)clear {
    self.uri = nil;
    self.seeking = NO;
    self.end = 0;
    [self.timer invalidate];
    self.timer = nil;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (self.uri && ![self.uri isEqualToString:SGURIString(state.track.URI)]) [self clear];
}

- (void)tick:(NSTimer *)timer {
    SPTPlayerState *state = SGPlayerState();
    if (!SGFlag(SGKeyABLoop, NO) || ![self.uri isEqualToString:SGURIString(state.track.URI)]) {
        [self clear];
        return;
    }
    if (!state.isPlaying || state.isPaused || state.isLoading) return;
    double position = state.position;
    if (!isfinite(position)) return;
    if (position < self.end) {
        self.seeking = NO;
    } else if (!self.seeking) {
        id<SPTPlayer> player = SGPlayer();
        if (![player respondsToSelector:@selector(seekTo:)]) return;
        self.seeking = YES;
        [player seekTo:self.start];
    }
}

- (void)mark:(NSString *)uri end:(BOOL)end {
    SPTPlayerState *state = SGPlayerState();
    if (!SGFlag(SGKeyABLoop, NO) || ![uri isEqualToString:SGURIString(state.track.URI)]) return;
    double position = state.isPaused ? state.positionAsOfTimestamp : state.position;
    if (!isfinite(position) || !isfinite(state.duration) || position < 0 || position >= state.duration) return;
    if (!end) {
        if (state.duration - position <= kMinimumLoop) return;
        [self clear];
        self.uri = uri;
        self.start = position;
        return;
    }
    if (![self.uri isEqualToString:uri] || position - self.start < kMinimumLoop) return;
    self.end = position;
    [self.timer invalidate];
    self.timer = [NSTimer timerWithTimeInterval:0.05 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

@end

static NSString *timeLabel(double seconds) {
    NSInteger whole = (NSInteger)seconds;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(whole / 60), (long)(whole % 60)];
}

UIMenu *SGABLoopMenu(void) {
    static SGABLoop *loop;
    if (!SGFlag(SGKeyABLoop, NO)) {
        [loop clear];
        return nil;
    }
    SPTPlayerState *state = SGPlayerState();
    NSString *uri = SGURIString(state.track.URI);
    if (!([uri hasPrefix:@"spotify:track:"] || [uri hasPrefix:@"spotify:local:"]) || !(state.duration > kMinimumLoop)) return nil;
    if (!loop) {
        loop = [SGABLoop new];
        SGAddPlayerStateObserver(loop);
    }
    BOOL hasStart = [loop.uri isEqualToString:uri];
    UIAction *start = [UIAction actionWithTitle:@"Set Start (A)" image:nil identifier:nil handler:^(UIAction *action) {
        [loop mark:uri end:NO];
    }];
    UIAction *end = [UIAction actionWithTitle:@"Set End (B)" image:nil identifier:nil handler:^(UIAction *action) {
        [loop mark:uri end:YES];
    }];
    if (!hasStart || (state.isPaused ? state.positionAsOfTimestamp : state.position) - loop.start < kMinimumLoop)
        end.attributes = UIMenuElementAttributesDisabled;
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray arrayWithArray:@[start, end]];
    if (hasStart) {
        [actions addObject:[UIAction actionWithTitle:@"Clear Loop" image:nil identifier:nil handler:^(UIAction *action) {
            if ([loop.uri isEqualToString:uri]) [loop clear];
        }]];
    }
    UIMenu *menu = [UIMenu menuWithTitle:@"A–B Loop" image:[UIImage systemImageNamed:@"repeat"] identifier:nil options:0 children:actions];
    menu.subtitle = !hasStart ? @"Off" : loop.end > 0
        ? [NSString stringWithFormat:@"%@–%@", timeLabel(loop.start), timeLabel(loop.end)]
        : [NSString stringWithFormat:@"Start: %@", timeLabel(loop.start)];
    return menu;
}
