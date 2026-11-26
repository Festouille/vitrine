// CarPlay Simulator harness for Vitrine's Shared/CarPlay module.
// Compiles the real CarPlay.x hooks and SGCarPlayModel.m with a mock Spotify playback/lyrics backend
// so CarPlay Now Playing, Synced Lyrics (with translations + tap-to-seek), Controls, and the
// sideload crash guard can be exercised live in the Xcode CarPlay Simulator and verified via unit assertions.
#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGLocalize.h"
#import "Shared/CarPlay/CarPlay.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Player/SleepTimer.h"
#import "Shared/Sing/Sing.h"
#import "Shared/AudioEffects/AudioEffects.h"

#pragma mark - Mock Spotify & Vitrine Backend

NSNotificationName const SGKaraokeLinesKeptNotification = @"SGKaraokeLinesKeptNotification";
NSNotificationName const SGKaraokeLinesInvalidatedNotification = @"SGKaraokeLinesInvalidatedNotification";

static NSString *gTrackID = @"track-midnight-drive";
static NSString *gTrackTitle = @"Midnight City";
static NSString *gTrackArtist = @"M83";
static NSString *gTrackAlbum = @"Hurry Up, We're Dreaming";
static NSInteger gPositionMs = 42500;
static NSInteger gDurationMs = 243000;
static BOOL gPaused = NO;
static double gSpeed = 1.0;
static SGSleepTimerMode gSleepMode = SGSleepTimerOff;
static NSDate *gSleepEnd = nil;
static BOOL gSingOn = NO;
static BOOL gDSPOn = YES;
static NSInteger gLastSeekMs = -1;
static NSArray<SGKaraokeLine *> *gMockLines = nil;
static NSMutableArray<id<SGPlayerStateObserver>> *gObservers = nil;

// Enable CarPlay before CarPlay.x's %ctor runs (constructor priority 101 runs before default 65535).
__attribute__((constructor(101))) static void enableCarPlayForHarness(void) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setBool:YES forKey:SGKeyCarPlay];
    [ud setBool:YES forKey:SGKeyCarPlayLyrics];
    [ud setBool:YES forKey:SGKeyCarPlayNowPlayingLine];
    [ud setBool:YES forKey:SGKeyCarPlayTranslations];
    [ud setBool:YES forKey:SGKeyCarPlayControls];
    [ud setBool:YES forKey:SGKeyCarPlayCrashFix];
    [ud setBool:NO forKey:SGKeyLockScreenLyrics];
    [ud synchronize];
}

static NSArray<SGKaraokeLine *> *buildSampleLines(void) {
    NSArray<NSDictionary *> *raw = @[
        @{ @"ms": @12000, @"end": @20000, @"t": @"Waiting in a car", @"tr": @"En attendant dans une voiture" },
        @{ @"ms": @20500, @"end": @29000, @"t": @"Waiting for a ride in the dark", @"tr": @"En attendant un trajet dans le noir" },
        @{ @"ms": @30000, @"end": @39000, @"t": @"The night city grows", @"tr": @"La ville nocturne grandit" },
        @{ @"ms": @40000, @"end": @49000, @"t": @"Look and see her eyes, they glow", @"tr": @"Regarde ses yeux, ils brillent" },
        @{ @"ms": @50000, @"end": @59000, @"t": @"Waiting in a car", @"tr": @"En attendant dans une voiture" },
        @{ @"ms": @60000, @"end": @69000, @"t": @"Waiting for the right time", @"tr": @"En attendant le bon moment" },
        @{ @"ms": @70000, @"end": @80000, @"t": @"Waiting in a car", @"tr": @"En attendant dans une voiture" },
        @{ @"ms": @81000, @"end": @92000, @"t": @"Waiting for the right time", @"tr": @"En attendant le bon moment" },
        @{ @"ms": @95000, @"end": @106000, @"t": @"The city is my church", @"tr": @"La ville est mon église" },
        @{ @"ms": @107000, @"end": @118000, @"t": @"It wraps me in the sparkling twilight", @"tr": @"Elle m'enveloppe dans le crépuscule étincelant" },
    ];
    NSMutableArray<SGKaraokeLine *> *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (NSDictionary *d in raw) {
        SGKaraokeWord *w = [SGKaraokeWord new];
        w.text = d[@"t"];
        w.start = [d[@"ms"] integerValue];
        w.end = [d[@"end"] integerValue];
        SGKaraokeLine *line = [SGKaraokeLine new];
        line.start = w.start;
        line.end = w.end;
        line.words = @[w];
        line.timing = SGKaraokeTimingLine;
        line.translation = d[@"tr"];
        [out addObject:line];
    }
    return out;
}

static void notifyPlayerObservers(void) {
    for (id<SGPlayerStateObserver> obs in [gObservers copy]) {
        [obs playerStateDidChange:nil];
    }
}

static UIImage *makeAlbumArt(void) {
    CGSize sz = CGSizeMake(512, 512);
    UIGraphicsBeginImageContextWithOptions(sz, YES, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (id)[UIColor colorWithRed:0.06 green:0.08 blue:0.20 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.45 green:0.12 blue:0.48 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.08 green:0.55 blue:0.65 alpha:1.0].CGColor,
    ];
    CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(ctx, grad, CGPointZero, CGPointMake(512, 512), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);

    UIImage *note = [UIImage systemImageNamed:@"car.fill"
                            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:160 weight:UIImageSymbolWeightBold]];
    [[UIColor colorWithWhite:1.0 alpha:0.9] setFill];
    [note drawInRect:CGRectMake(156, 176, 200, 160)];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static void publishNowPlayingInfo(void) {
    UIImage *artImg = makeAlbumArt();
    MPMediaItemArtwork *art = [[MPMediaItemArtwork alloc] initWithBoundsSize:artImg.size requestHandler:^UIImage *(CGSize size) {
        return artImg;
    }];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = gTrackTitle;
    info[MPMediaItemPropertyArtist] = gTrackArtist;
    info[MPMediaItemPropertyAlbumTitle] = gTrackAlbum;
    info[MPMediaItemPropertyPlaybackDuration] = @(gDurationMs / 1000.0);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(gPositionMs / 1000.0);
    info[MPNowPlayingInfoPropertyPlaybackRate] = gPaused ? @0.0 : @(gSpeed);
    info[MPMediaItemPropertyArtwork] = art;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
    MPNowPlayingInfoCenter.defaultCenter.playbackState = gPaused ? MPNowPlayingPlaybackStatePaused : MPNowPlayingPlaybackStatePlaying;
}

#pragma mark - Stubbed Vitrine C APIs

void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!gObservers) gObservers = [NSMutableArray array];
    if (observer && ![gObservers containsObject:observer]) [gObservers addObject:observer];
}

SPTPlayerState *SGPlayerState(void) { return nil; }

NSString *SGKaraokePlayingTrack(void) { return gTrackID; }
NSInteger SGKaraokePositionMs(void) { return gPositionMs; }
NSInteger SGKaraokeDelayMs(void) { return 0; }
BOOL SGKaraokeLooking(NSString *trackID) { return NO; }
void SGKaraokeRequestLyrics(NSString *trackID) {}

NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) {
    if (!gMockLines) gMockLines = buildSampleLines();
    return [trackID isEqualToString:gTrackID] ? gMockLines : nil;
}

void SGKaraokeSeek(NSInteger ms) {
    gLastSeekMs = MAX(0, MIN(ms, gDurationMs));
    gPositionMs = gLastSeekMs;
    publishNowPlayingInfo();
    notifyPlayerObservers();
}

double SGPlayerSpeed(void) { return gSpeed; }
BOOL SGPlayerSpeedAllowed(void) { return YES; }
void SGSetPlayerSpeed(double speed) {
    gSpeed = speed;
    publishNowPlayingInfo();
}

SGSleepTimerMode SGSleepTimerCurrentMode(void) { return gSleepMode; }
NSDate *SGSleepTimerEnd(void) { return gSleepEnd; }
void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds) {
    gSleepMode = mode;
    gSleepEnd = (mode == SGSleepTimerAtTime && seconds > 0) ? [NSDate dateWithTimeIntervalSinceNow:seconds] : nil;
}

SGSingState SGSingCurrentState(void) { return gSingOn ? SGSingStateSinging : SGSingStateOff; }
SGSingModelState SGSingModelCurrentState(void) { return SGSingModelReady; }
BOOL SGSingOn(void) { return gSingOn; }
void SGSetSingOn(BOOL on) { gSingOn = on; }

BOOL SGDSPSwitch(NSString *key) {
    return [key isEqualToString:SGKeyDSP] ? gDSPOn : NO;
}
void SGDSPSetSwitch(NSString *key, BOOL on) {
    if ([key isEqualToString:SGKeyDSP]) gDSPOn = on;
}

#pragma mark - Automated Self-Test Suite

static int gFailures = 0;

static void check(BOOL cond, const char *name) {
    if (cond) {
        fprintf(stderr, "PASS: %s\n", name);
    } else {
        fprintf(stderr, "FAIL: %s\n", name);
        gFailures++;
    }
}

static void runUnitAndHookTests(void) {
    NSArray<SGKaraokeLine *> *lines = buildSampleLines();

    // 1. SGCarPlayLyricsEntries: active line, 1-line lookback, translations, seekable
    NSInteger activeIdx = -1;
    NSArray<SGCarPlayLyricEntry *> *entries = SGCarPlayLyricsEntries(lines, 42500, 0, YES, NO, NO, 6, &activeIdx);
    check(entries.count == 5, "lyrics entries window from anchor-1 (2..6) within maxItems=6");
    check(activeIdx == 3, "outActiveIndex reports global active line index 3");
    check(entries[0].lineIndex == 2, "entry 0 is prior line (index 2)");
    check(entries[1].lineIndex == 3 && entries[1].active, "entry 1 is active line (index 3) with 1-line lookback");
    check([entries[1].text isEqualToString:@"Look and see her eyes, they glow"], "active lyric text matches");
    check([entries[1].detail isEqualToString:@"Regarde ses yeux, ils brillent"], "translation populates detail");
    check(entries[1].seekable, "timed lyric entries are seekable");

    // 2. SGCarPlayLyricsEntries without translations
    NSArray<SGCarPlayLyricEntry *> *noTrans = SGCarPlayLyricsEntries(lines, 42500, 0, NO, NO, NO, 10, &activeIdx);
    check(noTrans[1].detail == nil, "translations omitted when showTranslations=NO");

    // 3. Untimed lyrics are not seekable and have no active line
    SGKaraokeWord *uw = [SGKaraokeWord new];
    uw.text = @"Plain unsynced line";
    SGKaraokeLine *untimed = [SGKaraokeLine new];
    untimed.start = 0;
    untimed.words = @[uw];
    untimed.timing = SGKaraokeTimingNone;
    NSArray<SGCarPlayLyricEntry *> *untimedEntries = SGCarPlayLyricsEntries(@[untimed], 42500, 0, YES, NO, NO, 10, &activeIdx);
    check(untimedEntries.count == 1 && !untimedEntries[0].seekable && activeIdx == -1, "untimed lyrics non-seekable and inactive");

    // 4. SGCarPlayNowPlayingLyricLine
    NSInteger msToChange = -1;
    NSString *npLine = SGCarPlayNowPlayingLyricLine(lines, 42500, 0, NO, NO, NO, &msToChange);
    check([npLine isEqualToString:@"Look and see her eyes, they glow"], "Now Playing lyric line matches active line");
    check(msToChange > 0 && msToChange <= 10000, "msToChange reports time until next line");

    NSString *npLineTrans = SGCarPlayNowPlayingLyricLine(lines, 42500, 0, YES, NO, NO, NULL);
    check([npLineTrans isEqualToString:@"Regarde ses yeux, ils brillent"],
          "Now Playing lyric line prefers translation when enabled");

    // 5. SGCarPlayMergedButtons: 4 Spotify buttons (including More) + 2 Vitrine buttons -> capped at 5, More displaced
    UIImage *dot = [UIImage systemImageNamed:@"circle.fill"];
    CPNowPlayingButton *b1 = [[CPNowPlayingShuffleButton alloc] initWithHandler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *b2 = [[CPNowPlayingRepeatButton alloc] initWithHandler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *b3 = [[CPNowPlayingImageButton alloc] initWithImage:dot handler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *bMore = [[CPNowPlayingMoreButton alloc] initWithHandler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *v1 = [[CPNowPlayingImageButton alloc] initWithImage:dot handler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *v2 = [[CPNowPlayingImageButton alloc] initWithImage:dot handler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *displaced = nil;
    NSArray<CPNowPlayingButton *> *merged = SGCarPlayMergedButtons(@[b1, b2, b3, bMore], @[v1, v2], &displaced);
    check(merged.count == 5, "merged buttons respect Apple 5-button maximum");
    check(displaced == bMore, "displaced CPNowPlayingMoreButton returned for overflow");
    check([merged containsObject:v1] && [merged containsObject:v2], "both Vitrine buttons present in merged list");

    // 6. Speed presets & formatting
    NSArray<NSNumber *> *presets = SGCarPlaySpeedPresets();
    check(presets.count == 5 && [presets[1] doubleValue] == 1.0, "speed presets include 1.0x");
    check([SGCarPlayFormatSpeed(1.0) isEqualToString:@"1.0×"], "1.0 speed formats cleanly");
    check([SGCarPlayFormatSpeed(1.25) isEqualToString:@"1.25×"], "1.25 speed formats cleanly");

    // 7. Sleep timer formatting
    NSDate *now = [NSDate dateWithTimeIntervalSinceReferenceDate:100000];
    check([SGCarPlayFormatSleepTimer(SGSleepTimerOff, nil, now) isEqualToString:@"Off"], "sleep timer Off");
    check([SGCarPlayFormatSleepTimer(SGSleepTimerEndOfTrack, nil, now) isEqualToString:@"End of track"], "sleep timer End of track");
    check([SGCarPlayFormatSleepTimer(SGSleepTimerAtTime, [now dateByAddingTimeInterval:900], now) isEqualToString:@"15 min left"], "sleep timer countdown");

    // 8. Live hook verification: CPNowPlayingTemplate updateNowPlayingButtons: injects Lyrics + Controls <= 5
    CPNowPlayingTemplate *np = CPNowPlayingTemplate.sharedTemplate;
    [np updateNowPlayingButtons:@[b1, b2, b3, bMore]];
    check(np.nowPlayingButtons.count == 5, "CPNowPlayingTemplate hook merges to 5 buttons");

    // 9. Sideload crash guard: verify CPListTemplate setAssistantCellConfiguration: does not throw
    CPListTemplate *list = [[CPListTemplate alloc] initWithTitle:@"Test" sections:@[]];
    BOOL threw = NO;
    @try {
        list.assistantCellConfiguration = nil;
    } @catch (NSException *ex) {
        threw = YES;
    }
    check(!threw, "CPListTemplate assistantCellConfiguration guard safe");

    fprintf(stderr, "CARPLAY_TESTS_DONE failures=%d\n", gFailures);
}

#pragma mark - CarPlay Scene Delegate

static CPInterfaceController *gCarPlayIC = nil;

static void configureSpotifyNowPlayingButtons(void) {
    UIImage *heart = [UIImage systemImageNamed:@"heart.fill"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]];
    CPNowPlayingButton *shuffle = [[CPNowPlayingShuffleButton alloc] initWithHandler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *repeat = [[CPNowPlayingRepeatButton alloc] initWithHandler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *like = [[CPNowPlayingImageButton alloc] initWithImage:heart handler:^(CPNowPlayingButton *b) {}];
    CPNowPlayingButton *more = [[CPNowPlayingMoreButton alloc] initWithHandler:^(CPNowPlayingButton *b) {}];
    // Our real CarPlay.x %hook CPNowPlayingTemplate intercepts this call and merges Lyrics + Controls!
    [CPNowPlayingTemplate.sharedTemplate updateNowPlayingButtons:@[shuffle, repeat, like, more]];
}

static void pushTargetScreen(NSString *screen) {
    CPNowPlayingTemplate *np = CPNowPlayingTemplate.sharedTemplate;
    configureSpotifyNowPlayingButtons();
    publishNowPlayingInfo();
    notifyPlayerObservers();

    if ([screen isEqualToString:@"nowplaying"]) {
        [gCarPlayIC pushTemplate:np animated:NO completion:nil];
        return;
    }

    // Push Now Playing first, then trigger Vitrine's injected Lyrics or Controls button handler!
    [gCarPlayIC pushTemplate:np animated:NO completion:^(BOOL ok, NSError *err) {
        NSArray<CPNowPlayingButton *> *btns = np.nowPlayingButtons;
        CPNowPlayingButton *target = nil;
        if ([screen isEqualToString:@"lyrics"] && btns.count >= 2) {
            target = btns[btns.count - 2];
        } else if ([screen isEqualToString:@"controls"] && btns.count >= 1) {
            target = btns[btns.count - 1];
        }
        if (target) {
            if ([target respondsToSelector:@selector(handlePrimaryAction)]) {
                [target performSelector:@selector(handlePrimaryAction)];
            } else {
                void (^handler)(CPNowPlayingButton *) = [target valueForKey:@"handler"];
                if (handler) handler(target);
            }
        }
    }];
}

static void openCarPlayScreen(NSString *screen) {
    if (!gCarPlayIC) return;
    if (gCarPlayIC.templates.count > 1) {
        [gCarPlayIC popToRootTemplateAnimated:NO completion:^(BOOL ok, NSError *err) {
            pushTargetScreen(screen);
        }];
    } else if (gCarPlayIC.templates.count == 1) {
        pushTargetScreen(screen);
    } else {
        CPListItem *nowPlayingItem = [[CPListItem alloc] initWithText:gTrackTitle detailText:gTrackArtist];
        nowPlayingItem.playing = YES;
        CPListSection *sec = [[CPListSection alloc] initWithItems:@[nowPlayingItem] header:@"Recently Played" sectionIndexTitle:nil];
        CPListTemplate *root = [[CPListTemplate alloc] initWithTitle:@"Spotify · Vitrine" sections:@[sec]];
        [gCarPlayIC setRootTemplate:root animated:NO completion:^(BOOL ok, NSError *err) {
            pushTargetScreen(screen);
        }];
    }
}

@interface SGCarPlaySceneDelegate : UIResponder <CPTemplateApplicationSceneDelegate>
@end

@implementation SGCarPlaySceneDelegate

static void onDarwinScreenChange(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    NSString *n = (__bridge NSString *)name;
    NSString *screen = @"nowplaying";
    if ([n hasSuffix:@".lyrics"]) screen = @"lyrics";
    else if ([n hasSuffix:@".controls"]) screen = @"controls";
    dispatch_async(dispatch_get_main_queue(), ^{
        openCarPlayScreen(screen);
    });
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene
   didConnectInterfaceController:(CPInterfaceController *)interfaceController {
    gCarPlayIC = interfaceController;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFNotificationCenterRef nc = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(nc, NULL, onDarwinScreenChange, CFSTR("com.vitrine.carplay.nowplaying"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(nc, NULL, onDarwinScreenChange, CFSTR("com.vitrine.carplay.lyrics"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(nc, NULL, onDarwinScreenChange, CFSTR("com.vitrine.carplay.controls"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    });

    CPListItem *nowPlayingItem = [[CPListItem alloc] initWithText:gTrackTitle detailText:gTrackArtist];
    nowPlayingItem.playing = YES;
    nowPlayingItem.handler = ^(id<CPSelectableListItem> item, dispatch_block_t completionBlock) {
        openCarPlayScreen(@"nowplaying");
        completionBlock();
    };
    CPListSection *sec = [[CPListSection alloc] initWithItems:@[nowPlayingItem] header:@"Recently Played" sectionIndexTitle:nil];
    CPListTemplate *root = [[CPListTemplate alloc] initWithTitle:@"Spotify · Vitrine" sections:@[sec]];

    [interfaceController setRootTemplate:root animated:NO completion:^(BOOL ok, NSError *err) {
        NSString *screen = @"nowplaying";
        for (NSString *arg in NSProcessInfo.processInfo.arguments) {
            if ([arg hasPrefix:@"screen="]) screen = [arg substringFromIndex:7];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            openCarPlayScreen(screen);
        });
    }];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene
didDisconnectInterfaceController:(CPInterfaceController *)interfaceController {
    if (gCarPlayIC == interfaceController) gCarPlayIC = nil;
}

@end

#pragma mark - iPhone Companion Scene Delegate

@interface SGPhoneSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGPhoneSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *ws = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:ws];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];

    UILabel *title = [UILabel new];
    title.text = @"Vitrine CarPlay Harness";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *sub = [UILabel new];
    sub.text = @"Open I/O → External Displays → CarPlay\nin Simulator to view CarPlay templates.";
    sub.font = [UIFont systemFontOfSize:14];
    sub.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    sub.numberOfLines = 0;
    sub.textAlignment = NSTextAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, sub]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:vc.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:vc.view.trailingAnchor constant:-24],
    ]];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    publishNowPlayingInfo();

    if ([NSProcessInfo.processInfo.arguments containsObject:@"test"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            runUnitAndHookTests();
            exit(gFailures == 0 ? 0 : 1);
        });
    }
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    if ([connectingSceneSession.role isEqualToString:CPTemplateApplicationSceneSessionRoleApplication]) {
        UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"CarPlayScene" sessionRole:connectingSceneSession.role];
        cfg.delegateClass = SGCarPlaySceneDelegate.class;
        return cfg;
    }
    UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"PhoneScene" sessionRole:connectingSceneSession.role];
    cfg.delegateClass = SGPhoneSceneDelegate.class;
    return cfg;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
