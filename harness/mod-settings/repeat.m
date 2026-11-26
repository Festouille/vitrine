#import "Shared/Player/PlayerState.h"

@interface SPTPlayerTrack ()
@property (nonatomic, readwrite) id URI;
@end
@implementation SPTPlayerTrack
@synthesize URI = _URI;
@end

@interface SPTPlayerOptions ()
@property (nonatomic, readwrite) BOOL repeatingContext, repeatingTrack;
@end
@implementation SPTPlayerOptions
@synthesize repeatingContext = _repeatingContext, repeatingTrack = _repeatingTrack;
@end

@interface SPTPlayerState ()
@property (nonatomic, readwrite) SPTPlayerTrack *track;
@property (nonatomic, readwrite) SPTPlayerOptions *options;
@property (nonatomic, readwrite) BOOL isLoading;
@property (nonatomic, readwrite) id contextURI;
@end
@implementation SPTPlayerState
@synthesize track = _track, options = _options, isLoading = _isLoading;
@end

@interface SPTPlayerOptionOverrides : NSObject
@property (nonatomic) NSNumber *repeatingContext, *repeatingTrack;
@end
@implementation SPTPlayerOptionOverrides
@end

@protocol HarnessPlayerObserver <NSObject>
- (void)player:(id)player stateDidChange:(SPTPlayerState *)state;
@end

@interface SPTEsperantoPlayer : NSObject
@property (nonatomic) SPTPlayerState *state;
@property (nonatomic) NSHashTable<id<HarnessPlayerObserver>> *observers;
@property (nonatomic) NSUInteger repeatCommands;
@property (nonatomic) BOOL repeatRestricted, delayRepeatReport;
@property (nonatomic, copy) NSString *trackURI, *contextURI;
- (void)addPlayerObserver:(id)observer;
- (void)reportContext:(BOOL)context track:(BOOL)track loading:(BOOL)loading;
- (id)setRepeatingContext:(BOOL)on;
- (id)setRepeatingTrack:(BOOL)on;
- (id)setOptions:(SPTPlayerOptionOverrides *)options loggingParams:(id)logging;
@end

@implementation SPTEsperantoPlayer
- (instancetype)init {
    if ((self = [super init])) {
        self.observers = [NSHashTable weakObjectsHashTable];
        self.trackURI = @"spotify:track:repeat-harness";
        self.contextURI = @"spotify:playlist:repeat-harness";
    }
    return self;
}
- (void)addPlayerObserver:(id)observer {
    [self.observers addObject:observer];
}
- (void)reportContext:(BOOL)context track:(BOOL)track loading:(BOOL)loading {
    SPTPlayerState *state = [SPTPlayerState new];
    state.track = [SPTPlayerTrack new];
    state.track.URI = self.trackURI;
    state.contextURI = self.contextURI;
    state.isLoading = loading;
    state.options = [SPTPlayerOptions new];
    state.options.repeatingContext = context;
    state.options.repeatingTrack = track;
    self.state = state;
    for (id<HarnessPlayerObserver> observer in self.observers.allObjects) {
        if ([observer respondsToSelector:@selector(player:stateDidChange:)]) [observer player:self stateDidChange:state];
    }
}
- (id)setRepeatingContext:(BOOL)on {
    self.repeatCommands++;
    if (self.repeatRestricted) return @NO;
    [self reportContext:on track:self.state.options.repeatingTrack loading:NO];
    return @YES;
}
- (id)setRepeatingTrack:(BOOL)on {
    self.repeatCommands++;
    if (self.repeatRestricted) return @NO;
    [self reportContext:self.state.options.repeatingContext track:on loading:NO];
    return @YES;
}
- (id)setOptions:(SPTPlayerOptionOverrides *)options loggingParams:(id)logging {
    self.repeatCommands++;
    if (self.delayRepeatReport) return @YES;
    [self reportContext:options.repeatingContext ? options.repeatingContext.boolValue : self.state.options.repeatingContext
                  track:options.repeatingTrack ? options.repeatingTrack.boolValue : self.state.options.repeatingTrack loading:NO];
    return @YES;
}
@end

static SPTEsperantoPlayer *sg_repeatPlayer;
static UILabel *sg_repeatStatus;

BOOL SGHarnessRepeatAction(NSString *verb, NSString *value, UIViewController *page) {
    if (![verb hasPrefix:@"repeat-"]) return NO;
    NSArray *parts = [value componentsSeparatedByString:@","];
    NSString *mode = parts.firstObject;
    BOOL track = [mode isEqualToString:@"track"], context = track || [mode isEqualToString:@"context"];
    NSCAssert(context || track || [mode isEqualToString:@"off"], @"Unknown repeat mode: %@", mode);
    if ([verb isEqualToString:@"repeat-start"]) {
        sg_repeatPlayer = [SPTEsperantoPlayer new];
        sg_repeatPlayer.repeatRestricted = [parts.lastObject isEqualToString:@"restricted"];
        [sg_repeatPlayer reportContext:NO track:NO loading:YES];
        [sg_repeatPlayer addPlayerObserver:[NSObject new]];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSCAssert(sg_repeatPlayer.repeatCommands == 0, @"Restored before Spotify finished loading");
            [sg_repeatPlayer reportContext:context track:track loading:NO];
        });
    } else if ([verb isEqualToString:@"repeat-report"]) {
        [sg_repeatPlayer reportContext:context track:track loading:NO];
    } else if ([verb isEqualToString:@"repeat-context"]) {
        sg_repeatPlayer.contextURI = @"spotify:album:repeat-harness";
        sg_repeatPlayer.repeatRestricted = NO;
        [sg_repeatPlayer reportContext:context track:track loading:NO];
    } else if ([verb isEqualToString:@"repeat-next"]) {
        sg_repeatPlayer.trackURI = @"spotify:track:repeat-harness-next";
        [sg_repeatPlayer reportContext:context track:track loading:NO];
    } else if ([verb isEqualToString:@"repeat-set"]) {
        SPTPlayerOptionOverrides *options = [SPTPlayerOptionOverrides new];
        options.repeatingContext = @(context);
        options.repeatingTrack = @(track);
        sg_repeatPlayer.delayRepeatReport = [parts.lastObject isEqualToString:@"delayed"];
        [sg_repeatPlayer setOptions:options loggingParams:nil];
    } else if ([verb isEqualToString:@"repeat-set-context"]) {
        [sg_repeatPlayer setRepeatingContext:context];
    } else if ([verb isEqualToString:@"repeat-check"]) {
        SPTPlayerOptions *options = sg_repeatPlayer.state.options;
        NSString *actual = options.repeatingTrack ? @"track" : options.repeatingContext ? @"context" : @"off";
        NSCAssert([actual isEqualToString:mode] && options.repeatingContext == context && parts.count == 2 &&
                  sg_repeatPlayer.repeatCommands == (NSUInteger)[parts[1] integerValue],
                  @"Expected %@, saw %@ with %lu commands", value, actual, (unsigned long)sg_repeatPlayer.repeatCommands);
        if (!sg_repeatStatus) {
            UIView *host = page.navigationController.view;
            sg_repeatStatus = [UILabel new];
            sg_repeatStatus.translatesAutoresizingMaskIntoConstraints = NO;
            sg_repeatStatus.textAlignment = NSTextAlignmentCenter;
            sg_repeatStatus.backgroundColor = UIColor.blackColor;
            sg_repeatStatus.textColor = UIColor.whiteColor;
            sg_repeatStatus.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
            [host addSubview:sg_repeatStatus];
            [NSLayoutConstraint activateConstraints:@[
                [sg_repeatStatus.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
                [sg_repeatStatus.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
                [sg_repeatStatus.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor],
                [sg_repeatStatus.heightAnchor constraintEqualToConstant:28],
            ]];
        }
        sg_repeatStatus.text = [NSString stringWithFormat:@"Mock player repeat: %@", actual.capitalizedString];
        NSLog(@"[harness] repeat check passed: %@, %lu commands", actual, (unsigned long)sg_repeatPlayer.repeatCommands);
    } else {
        NSCAssert(NO, @"Unknown repeat action: %@", verb);
    }
    return YES;
}
