// A double tap on the player, read against the grid Settings draws: the recognizer, what each cell does
// and the playback controller it does it with. Which view of the player it goes on is each look's own
// hookup (Native/Player/PlayerGestures.x, Redesigned/Player/PlayerGestures.x), which call SGGestureAttach.
//
// The player already answers a sideways swipe with the next track and a vertical drag with the
// cards below, which leaves the double tap as the one gesture free to take.
#import "Core/SGCore.h"
#import "Gestures.h"
#import "Headers/SPTNowPlayingPlaybackController.h"

static __weak SPTNowPlayingPlaybackControllerImplementation *sg_player;
static void (^sg_observer)(SGGestureAction action);

void SGGestureSetObserver(void (^observer)(SGGestureAction action)) {
    sg_observer = [observer copy];
}

#pragma mark - what a cell does

static void perform(SGGestureAction action) {
    SPTNowPlayingPlaybackControllerImplementation *player = sg_player;
    if (!player) return;
    if (action != SGGestureNothing && sg_observer) sg_observer(action);
    switch (action) {
        case SGGestureNothing:
            break;
        case SGGestureSeekBack:
            if (player.seekingAllowed) [player seekBackwardBySeconds:SGGestureStep()];
            break;
        case SGGestureSeekForward:
            if (player.seekingAllowed) [player seekForwardBySeconds:SGGestureStep()];
            break;
        case SGGesturePlayPause:
            if (player.isPaused ? !player.disallowResuming : !player.disallowPausing) {
                [player setPaused:!player.isPaused];
            }
            break;
        case SGGestureNextTrack:
            if (player.canSkipNext) [player skipToNextWhileDragging:NO];
            break;
        case SGGesturePreviousTrack:
            [player skipToPreviousWhileDragging:NO];
            break;
        case SGGestureShuffle:
            [player setGlobalShuffleMode:!player.isShuffling];
            break;
        case SGGestureRepeat:
            [player toggleRepeatMode];
            break;
    }
}

#pragma mark - the recognizer

@interface SGGestureTarget : NSObject
@end

@implementation SGGestureTarget

- (void)doubleTapped:(UITapGestureRecognizer *)tap {
    // The recognizer outlives the switch: it stays on the player once attached, so the switch is
    // read here as well and the gesture stops the moment it goes off.
    if (!SGFlag(SGKeyGestures, NO)) return;
    // The host is the queue scrolled sideways, so a tap lands in content coordinates a few million
    // points out; its bounds origin is that scroll, and taking it off gives the point on screen.
    UIView *host = tap.view;
    CGRect visible = host.bounds;
    CGPoint point = [tap locationInView:host];
    point.x -= visible.origin.x;
    point.y -= visible.origin.y;
    NSInteger cell = SGGestureCellAt(point, visible.size);
    NSArray<NSNumber *> *zones = SGGestureZones();
    if (cell < 0 || cell >= (NSInteger)zones.count) return;
    perform((SGGestureAction)zones[(NSUInteger)cell].integerValue);
}

@end

static SGGestureTarget *target(void) {
    static SGGestureTarget *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGGestureTarget new]; });
    return shared;
}

// Spotify's own single tap on the player scrolls it to the cards below, and would fire on the first
// of a pair as well; every one above the artwork is asked to wait for the double tap to miss.
static void yieldSingleTaps(UIView *host, UITapGestureRecognizer *tap) {
    for (UIView *view = host; view; view = view.superview) {
        for (UIGestureRecognizer *other in view.gestureRecognizers) {
            if (other == tap || ![other isKindOfClass:UITapGestureRecognizer.class]) continue;
            if (((UITapGestureRecognizer *)other).numberOfTapsRequired != 1) continue;
            [other requireGestureRecognizerToFail:tap];
        }
    }
}

static char kTapKey, kSeenKey;

// Spotify adds its own recognizers as the player's controllers load, which is not ordered against
// this hook: the count of what stands above the artwork is watched so a later one still yields.
static NSUInteger tapsAbove(UIView *host) {
    NSUInteger count = 0;
    for (UIView *view = host; view; view = view.superview) count += view.gestureRecognizers.count;
    return count;
}

void SGGestureAttach(UIView *host) {
    if (!host || !SGFlag(SGKeyGestures, NO)) return;
    UITapGestureRecognizer *tap = objc_getAssociatedObject(host, &kTapKey);
    if (!tap) {
        tap = [[UITapGestureRecognizer alloc] initWithTarget:target() action:@selector(doubleTapped:)];
        tap.numberOfTapsRequired = 2;
        [host addGestureRecognizer:tap];
        objc_setAssociatedObject(host, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *seen = objc_getAssociatedObject(host, &kSeenKey);
    NSUInteger now = tapsAbove(host);
    if (seen.unsignedIntegerValue == now) return;
    objc_setAssociatedObject(host, &kSeenKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    yieldSingleTaps(host, tap);
}

#pragma mark - mini player

@interface SGMiniPlayerGestureTarget : NSObject <UIGestureRecognizerDelegate>
@end

static BOOL miniPlayerGesturesEnabled(void) {
    return SGFlag(SGKeyMiniPlayerGestures, NO) && sg_player != nil;
}

@implementation SGMiniPlayerGestureTarget

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (!miniPlayerGesturesEnabled()) return NO;
    for (UIView *view = touch.view; view && view != gesture.view; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return NO;
    }
    return YES;
}

- (void)swiped:(UISwipeGestureRecognizer *)swipe {
    if (!miniPlayerGesturesEnabled()) return;
    perform(swipe.direction == UISwipeGestureRecognizerDirectionLeft ? SGGestureNextTrack : SGGesturePreviousTrack);
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan || !miniPlayerGesturesEnabled()) return;
    UIView *card = hold.view;
    UIViewController *presenter = card.window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    UIView *presentationView = presenter.viewIfLoaded;
    if (!presentationView || presenter.isBeingDismissed || ![card isDescendantOfView:presentationView]) return;
    SPTNowPlayingPlaybackControllerImplementation *player = sg_player;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Mini player"
                                                                  message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    void (^addAction)(NSString *, SGGestureAction, BOOL) = ^(NSString *title, SGGestureAction action, BOOL enabled) {
        UIAlertAction *item = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *selected) {
            if (miniPlayerGesturesEnabled()) perform(action);
        }];
        item.enabled = enabled;
        [menu addAction:item];
    };
    BOOL paused = player.isPaused;
    addAction(paused ? @"Play" : @"Pause", SGGesturePlayPause, paused ? !player.disallowResuming : !player.disallowPausing);
    addAction(player.isShuffling ? @"Turn shuffle off" : @"Turn shuffle on", SGGestureShuffle, YES);
    addAction(@"Change repeat mode", SGGestureRepeat, YES);
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = card;
    menu.popoverPresentationController.sourceRect = card.bounds;
    SGPresentDark(menu);
    [presenter presentViewController:menu animated:YES completion:nil];
}

@end

static void attachMiniPlayerGestures(UIViewController *bar) {
    static char kCardKey, kTargetKey;
    UIView *card = SGFindRemembered(bar.view, &kCardKey, ^BOOL(UIView *view) {
        return [view.accessibilityIdentifier isEqualToString:@"SPTNowPlayingBar"];
    });
    if (!card || objc_getAssociatedObject(card, &kTargetKey)) return;
    SGMiniPlayerGestureTarget *handler = [SGMiniPlayerGestureTarget new];
    objc_setAssociatedObject(card, &kTargetKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSNumber *direction in @[@(UISwipeGestureRecognizerDirectionLeft), @(UISwipeGestureRecognizerDirectionRight)]) {
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:handler action:@selector(swiped:)];
        swipe.direction = direction.unsignedIntegerValue;
        swipe.delegate = handler;
        [card addGestureRecognizer:swipe];
    }
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(held:)];
    hold.delegate = handler;
    [card addGestureRecognizer:hold];
}

#pragma mark - hooks

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    attachMiniPlayerGestures((UIViewController *)self);
}
%end

%hook SPTNowPlayingPlaybackControllerImplementation
- (id)initWithPlayer:(id)player testManager:(id)manager inStreamClient:(id)client {
    id controller = %orig;
    sg_player = controller;
    return controller;
}
%end

// A single tap on the cover is Spotify's way into the tilt mode, the artwork alone in 3D. That is
// the half of a double tap that misses, so while the zones are on it would open on the way to every
// gesture; the tap goes back to Spotify with the switch.
%ctor {
    %init;
    SGRequireClasses(@[@"SPTNowPlayingPlaybackControllerImplementation",
                       @"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
}
