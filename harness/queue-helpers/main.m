#import <UIKit/UIKit.h>
#import "Core/SGFlagForce.h"
#import "Core/SGUIMode.h"
#import "Core/SGViewTree.h"
#import "Shared/Player/QueueHelpers.h"

void SGHarnessTap(UIWindow *window, CGPoint point);

@interface SPTPlayerTrack ()
@property (nonatomic, readwrite) id URI;
@property (nonatomic, readwrite) NSDictionary<NSString *, NSString *> *metadata;
@end

@implementation SPTPlayerTrack
@dynamic artistURI, artistName, trackTitle, provider;
- (instancetype)initWithURI:(NSURL *)uri albumURI:(NSURL *)album artistURI:(NSURL *)artist andUID:(NSString *)uid {
    if ((self = [super init])) {
        self.URI = uri;
        self.metadata = @{@"duration": @"180000"};
    }
    return self;
}
@end

@interface SPTPlayerState ()
@property (nonatomic, readwrite) NSArray *future;
@end
@implementation SPTPlayerState
@dynamic track, sleepTimer, contextURI, options, isPaused, isPlaying, isLoading, position;
@dynamic positionAsOfTimestamp, timestamp, playbackSpeed, duration, reverse;
@end

@interface SPTask : NSObject
@end

@implementation SPTask
- (id)addCallback:(void (^)(id))callback on:(dispatch_queue_t)queue {
    dispatch_async(queue, ^{ callback(nil); });
    return self;
}
- (id)addErrorCallback:(void (^)(NSError *))callback on:(dispatch_queue_t)queue {
    return self;
}
@end

@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end
@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell : UICollectionViewCell @end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell @end
@interface _TtC14Queue_ViewImpl19QueueViewController : UIViewController @end
@implementation _TtC14Queue_ViewImpl19QueueViewController @end

static SPTPlayerState *sg_state;
static NSHashTable<id<SGPlayerStateObserver>> *sg_observers;
static NSMutableArray<NSURL *> *sg_submissions;
static NSString *sg_currentTrack = @"Midnight City";
static NSUInteger sg_plays, sg_menus, sg_reshuffles, sg_checks, sg_failures;

SPTPlayerState *SGPlayerState(void) { return sg_state; }
id SGPlayer(void) { return sg_state; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!sg_observers) sg_observers = [NSHashTable weakObjectsHashTable];
    [sg_observers addObject:observer];
}

static void report(NSArray *future) {
    sg_state.future = future;
    for (id<SGPlayerStateObserver> observer in sg_observers.allObjects) [observer playerStateDidReport:sg_state];
}

@interface SPTPlayerQueueWrapperImpl : NSObject @end
@implementation SPTPlayerQueueWrapperImpl
- (instancetype)initWithPlayer:(id)player { return [super init]; }
- (SPTask *)queueTrack:(SPTPlayerTrack *)track {
    [sg_submissions addObject:track.URI];
    report([sg_state.future arrayByAddingObject:track]);
    return [SPTask new];
}
@end

static void check(BOOL result, NSString *name) {
    sg_checks++;
    if (!result) {
        sg_failures++;
        printf("FAIL: %s\n", name.UTF8String);
    }
}

static UILabel *label(UIView *parent, NSString *text, UIFont *font, UIColor *color, CGRect frame) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = font;
    label.textColor = color;
    [parent addSubview:label];
    return label;
}

static CGPoint centerInWindow(UIView *v) {
    return [v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)) toView:nil];
}

@interface SGQueueHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIViewController *queue;
@property (nonatomic, strong) UILabel *submissions;
@property (nonatomic, strong) UILabel *order;
@property (nonatomic, strong) UIButton *reshuffle;
@end

@implementation SGQueueHarnessDelegate

- (void)play { sg_plays++; }
- (void)openMenu { sg_menus++; }

- (void)reshuffleAction {
    sg_reshuffles++;
    id first = sg_state.future[0], second = sg_state.future[1];
    NSMutableArray *next = [sg_state.future mutableCopy];
    next[0] = second;
    next[1] = first;
    report(next);
    self.order.text = @"1   The Less I Know the Better\n2   Space Song";
}

- (UICollectionViewCell *)song:(NSString *)name songID:(NSString *)songID playlist:(BOOL)playlist at:(CGFloat)y {
    Class cls = playlist ? _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class :
        _TtC12Element_List18CollectionViewCell.class;
    CGFloat width = self.window.bounds.size.width - 40;
    UICollectionViewCell *cell = [[cls alloc] initWithFrame:CGRectMake(20, y, width, 44)];
    cell.accessibilityIdentifier = playlist ? @"Playlist.ItemCell" : nil;
    UIView *row = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    row.accessibilityIdentifier = playlist ? @"Encore.ListRow" : @"Components.UI.RetrievalRowElementUI";
    [cell.contentView addSubview:row];
    UILabel *title = label(row, name, [UIFont systemFontOfSize:16], UIColor.whiteColor, CGRectMake(12, 0, width - 56, 44));
    if (playlist) title.accessibilityIdentifier = @"Track.Row.Content.Title";
    row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.09];
    row.layer.cornerRadius = 10;
    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
    more.frame = CGRectMake(width - 44, 0, 44, 44);
    more.tintColor = UIColor.whiteColor;
    [more setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    more.accessibilityIdentifier = [@"Components.UI.ContextMenuButton-" stringByAppendingString:songID];
    [more addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:more];
    [cell addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(play)]];
    [self.queue.view addSubview:cell];
    return cell;
}

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    sg_state = [SPTPlayerState new];
    sg_submissions = [NSMutableArray array];
    SPTPlayerTrack *a = [SPTPlayerTrack new], *b = [SPTPlayerTrack new];
    a.metadata = (id)@{@"duration": @300000};
    b.metadata = @{@"duration": @"240000"};
    report(@[a, b]);

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.queue = [_TtC14Queue_ViewImpl19QueueViewController new];
    self.window.rootViewController = self.queue;
    UIView *root = self.queue.view;
    BOOL redesigned = SGRedesignedUI();
    BOOL enabled = [NSProcessInfo.processInfo.arguments containsObject:@"--on"];
    root.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    root.backgroundColor = redesigned ? [UIColor colorWithRed:0.075 green:0.071 blue:0.10 alpha:1] :
        [UIColor colorWithWhite:0.075 alpha:1];
    CGFloat width = self.window.bounds.size.width;
    label(root, redesigned ? @"REDESIGNED · QUEUE HARNESS" : @"NATIVE · QUEUE HARNESS",
          [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold], UIColor.secondaryLabelColor,
          CGRectMake(20, 83, width - 40, 22));
    label(root, @"Queue and browsing", [UIFont systemFontOfSize:29 weight:UIFontWeightBold], UIColor.whiteColor,
          CGRectMake(20, 112, width - 40, 38));
    label(root, [@"Now playing: " stringByAppendingString:sg_currentTrack], [UIFont systemFontOfSize:15],
          UIColor.secondaryLabelColor, CGRectMake(20, 151, width - 40, 26));

    label(root, @"BROWSE SONGS", [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1], UIColor.secondaryLabelColor,
          CGRectMake(20, 201, width - 40, 20));
    UIView *album = [self song:@"Wake Me Up · Album" songID:@"5673WA8EEUSPx1ir26lhGW" playlist:NO at:228];
    UIView *playlist = [self song:@"Cry For Me · Playlist" songID:@"1234567890ABCDEFGHIJKL" playlist:YES at:280];
    UIView *unknown = [self song:@"Unsupported row" songID:@"not-a-song" playlist:NO at:332];
    self.submissions = label(root, @"Queued by tapping: 0", [UIFont systemFontOfSize:15], UIColor.secondaryLabelColor,
                             CGRectMake(20, 385, width - 40, 26));
    label(root, @"UP NEXT", [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1], UIColor.secondaryLabelColor,
          CGRectMake(20, 441, width - 40, 24));
    self.order = label(root, @"1   Space Song\n2   The Less I Know the Better", [UIFont systemFontOfSize:18],
                       UIColor.whiteColor, CGRectMake(20, 471, width - 40, 70));
    self.order.numberOfLines = 0;
    if ([SGForcedFlagValue(@"ios-feature-queue.is_reshuffle_enabled") isEqual:@YES]) {
        self.reshuffle = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *config = UIButtonConfiguration.filledButtonConfiguration;
        config.title = @"Reshuffle";
        config.image = [UIImage systemImageNamed:@"shuffle"];
        config.imagePadding = 8;
        config.baseBackgroundColor = redesigned ? [UIColor colorWithWhite:0.26 alpha:1] :
            [UIColor colorWithRed:0.12 green:0.72 blue:0.35 alpha:1];
        config.baseForegroundColor = UIColor.whiteColor;
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        self.reshuffle.configuration = config;
        self.reshuffle.frame = CGRectMake(20, 564, 143, 44);
        self.reshuffle.accessibilityIdentifier = @"reshuffle-button";
        [self.reshuffle addTarget:self action:@selector(reshuffleAction) forControlEvents:UIControlEventTouchUpInside];
        [root addSubview:self.reshuffle];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [root layoutIfNeeded];
        static char durationKey;
        UILabel *duration = (UILabel *)SGFindIdentifier(root, @"spotifyglass.queue.durationLabel", &durationKey);
        check(!enabled || [duration.text isEqualToString:@"About 9 min in queue"], @"duration excludes the playing track");
        check(enabled || duration == nil, @"duration is off by default");
        check((self.reshuffle != nil) == enabled, @"reshuffle respects the switch");
        check(SGForcedFlagValue(@"ios-feature-queue.is_swipe_to_play_next_enabled") == nil, @"reshuffle does not force related flags");
        check([SGQueueDurationText(nil) isEqualToString:@"Queue duration unavailable"], @"unavailable queue is not zero");
        report(@[]);
        check(!enabled || [duration.text isEqualToString:@"Queue is empty"], @"empty queue");
        report(@[a, [SPTPlayerTrack new]]);
        check(!enabled || [duration.text isEqualToString:@"At least 5 min in queue"], @"partial duration stays a lower bound");
        report(@[a, b]);
        SGHarnessTap(self.window, centerInWindow(album));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            SGHarnessTap(self.window, centerInWindow(playlist));
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            SGHarnessTap(self.window, centerInWindow(unknown));
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 750 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            SGHarnessTap(self.window, [album convertPoint:CGPointMake(album.bounds.size.width - 22, 22) toView:nil]);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (self.reshuffle) SGHarnessTap(self.window, centerInWindow(self.reshuffle));
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            check(sg_submissions.count == (enabled ? 2 : 0), @"only supported taps go to the queue");
            check(sg_plays == (enabled ? 1 : 3), @"tap-to-queue prevents playback without intercepting unsupported rows");
            check(sg_menus == 1, @"the menu button keeps its own action");
            check(!enabled || [sg_submissions.firstObject.absoluteString isEqual:@"spotify:track:5673WA8EEUSPx1ir26lhGW"], @"album row uses its track URI");
            check(!enabled || [sg_submissions.lastObject.absoluteString isEqual:@"spotify:track:1234567890ABCDEFGHIJKL"], @"playlist row uses its track URI");
            check(!enabled || [duration.text isEqualToString:@"About 15 min in queue"], @"duration updates after an add");
            check(sg_reshuffles == (enabled ? 1 : 0) && (!enabled || sg_state.future.firstObject == b), @"reshuffle changes upcoming order");
            check([sg_currentTrack isEqualToString:@"Midnight City"], @"queue operations keep the current track");
            self.submissions.text = [NSString stringWithFormat:@"Queued by tapping: %lu", (unsigned long)sg_submissions.count];
            printf("Queue helpers (%s, %s): %lu/%lu passed\n", redesigned ? "redesigned" : "native", enabled ? "on" : "off",
                   (unsigned long)(sg_checks - sg_failures), (unsigned long)sg_checks);
            fflush(stdout);
        });
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGQueueHarnessDelegate.class));
    }
}
