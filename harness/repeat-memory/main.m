#import "Core/SGPrefs.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/RepeatMode.h"

@implementation SPTPlayerTrack
- (instancetype)initWithURI:(NSString *)uri { if ((self = [super init])) _URI = [uri copy]; return self; }
@end

@implementation SPTPlayerOptions
- (instancetype)initWithBits:(NSUInteger)bits {
    if ((self = [super init])) {
        _repeatingContext = (bits & 1) != 0;
        _repeatingTrack = (bits & 2) != 0;
    }
    return self;
}
@end

@implementation SPTPlayerState
- (instancetype)initWithTrack:(NSString *)track context:(NSString *)context bits:(NSUInteger)bits loading:(BOOL)loading {
    if ((self = [super init])) {
        if (track) _track = [[SPTPlayerTrack alloc] initWithURI:track];
        _contextURI = [context copy];
        _options = [[SPTPlayerOptions alloc] initWithBits:bits];
        _isLoading = loading;
        _isPlaying = track && !loading;
    }
    return self;
}
@end

@interface SPTEsperantoPlayer : NSObject
@property SPTPlayerState *state;
@property NSMutableArray<NSString *> *commands;
@end
@implementation SPTEsperantoPlayer
- (void)addPlayerObserver:(id)observer {}
- (id)setRepeatingContext:(BOOL)on {
    [self.commands addObject:on ? @"context on" : @"context off"];
    return nil;
}
- (id)setRepeatingTrack:(BOOL)on {
    [self.commands addObject:on ? @"track on" : @"track off"];
    return nil;
}
- (id)setOptions:(id)options loggingParams:(id)logging { return nil; }
@end

__attribute__((objc_runtime_name("_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation")))
@interface NowPlayingPlatform : NSObject
- (void)player:(id)player stateDidChange:(id)state;
@end
@implementation NowPlayingPlatform
- (void)player:(id)player stateDidChange:(id)state {}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property UILabel *label;
@property NSUInteger total, passed;
@property SPTEsperantoPlayer *player;
@property NowPlayingPlatform *platform;
@end

@implementation AppDelegate
- (void)report:(NSString *)track context:(NSString *)context bits:(NSUInteger)bits loading:(BOOL)loading {
    self.player.state = [[SPTPlayerState alloc] initWithTrack:track context:context bits:bits loading:loading];
    [self.platform player:self.player stateDidChange:self.player.state];
}

- (void)check:(BOOL)passed text:(NSString *)text {
    self.total++;
    self.passed += passed;
    NSString *line = [NSString stringWithFormat:@"%@  %@", passed ? @"PASS" : @"FAIL", text];
    NSLog(@"%@", line);
    self.label.text = [self.label.text stringByAppendingFormat:@"\n\n%@", line];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.blackColor;
    self.label = [UILabel new];
    self.label.text = @"Vitrine · Repeat memory";
    self.label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.label.numberOfLines = 0;
    self.label.textColor = UIColor.whiteColor;
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:self.label];
    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor constant:24],
        [self.label.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor constant:-24],
        [self.label.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
    ]];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    self.platform = [NowPlayingPlatform new];
    self.player = [SPTEsperantoPlayer new];
    self.player.commands = [NSMutableArray new];
    [self.player addPlayerObserver:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *args = NSProcessInfo.processInfo.arguments;
        NSString *key = @"spotifyglass.rememberRepeatMode.last";
        NSString *track = @"spotify:track:first", *second = @"spotify:track:second", *context = @"spotify:playlist:one";
        if ([args containsObject:@"seed"]) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyRememberRepeatMode];
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
            SGPrefsChanged();
            [self report:track context:context bits:1 loading:NO];
            [self check:!SGFlag(SGKeyRememberRepeatMode, NO) && !self.player.commands.count text:@"Default off leaves Repeat alone."];
            SGSetEnabled(SGKeyRememberRepeatMode, YES);
            SGRepeatModeSettingChanged(YES);
            [self check:SGInt(key, -1) == 1 text:@"Enabling stores the current Repeat context."];
            [self.player setRepeatingTrack:YES];
            [self report:track context:context bits:1 loading:NO];
            [self check:SGInt(key, -1) == 1 text:@"Stale state does not acknowledge a new choice."];
            [self report:track context:context bits:3 loading:NO];
            [self check:SGInt(key, -1) == 3 text:@"Acknowledged Repeat One persists."];
            [NSUserDefaults.standardUserDefaults synchronize];
        } else {
            [self report:track context:context bits:0 loading:YES];
            [self check:!self.player.commands.count text:@"Loading report sends no commands."];
            [self report:track context:context bits:0 loading:NO];
            [self check:[self.player.commands isEqual:@[@"context on", @"track on"]] text:@"Cold launch restores stored Repeat One."];
            [self.player.commands removeAllObjects];
            [self report:track context:context bits:3 loading:NO];
            [self report:second context:context bits:0 loading:NO];
            [self check:[self.player.commands isEqual:@[@"context on", @"track on"]] text:@"Next track restores a reset Repeat One."];
            [self.player.commands removeAllObjects];
            [self report:second context:context bits:3 loading:NO];
            [self report:nil context:nil bits:0 loading:YES];
            [self report:second context:context bits:0 loading:NO];
            [self check:!self.player.commands.count text:@"Buffering the same track does not change Repeat."];
            if ([args containsObject:@"replay"]) {
                [self report:second context:context bits:3 loading:NO];
                [self.player setRepeatingTrack:NO];
                [self.player.commands removeAllObjects];
                [self report:nil context:nil bits:0 loading:NO];
                [self report:second context:context bits:0 loading:NO];
                [self check:[self.player.commands isEqual:@[@"context on", @"track on"]]
                       text:@"Replay after no playback restores Repeat One, not the unacknowledged choice."];
            }
        }
        NSLog(@"REPEAT %lu/%lu passed", (unsigned long)self.passed, (unsigned long)self.total);
    });
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
