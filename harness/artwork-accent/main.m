#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SGArtworkAccent.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Native/Appearance/Appearance.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Home/Home.h"

@interface SPTPlayerTrack ()
@property (nonatomic) id URI;
@property (nonatomic) NSDictionary *metadata;
@end
@implementation SPTPlayerTrack
- (NSString *)trackTitle { return @"Harness track"; }
@end

@interface SPTPlayerState ()
@property (nonatomic) SPTPlayerTrack *track;
@end
@implementation SPTPlayerState
- (BOOL)isPlaying { return YES; }
@end

@interface _TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation : NSObject
- (void)player:(id)player stateDidChange:(SPTPlayerState *)state;
@end
@implementation _TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation
- (void)player:(id)player stateDidChange:(SPTPlayerState *)state {}
@end

@interface _TtC19Home_FunkisPageImpl20FunkisViewController : UIViewController @end
@implementation _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; }
@end
@interface _TtC16Home_EvoPageImpl33EvoLoadableResourceViewController : UIViewController @end
@implementation _TtC16Home_EvoPageImpl33EvoLoadableResourceViewController
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; }
@end
@interface _TtC16Home_CarouselKit29TouchCancellingCollectionView : UICollectionView @end
@implementation _TtC16Home_CarouselKit29TouchCancellingCollectionView
- (void)layoutSubviews { [super layoutSubviews]; }
@end
@interface HomeHeaderElement : UIView @end
@implementation HomeHeaderElement @end
@interface HomeHeaderView : UIView @end
@implementation HomeHeaderView @end

static const NSInteger red = 0xB62031, blue = 0x1767CE, grey = 0x777777;
static NSString *const localURI = @"spotify:local:Artist:Album:Title:240";

static UIColor *color(NSInteger rgb) {
    return [UIColor colorWithRed:(rgb >> 16) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static UIImage *cover(NSInteger rgb) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(96, 96)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [color(rgb) setFill]; UIRectFill(CGRectMake(0, 0, 96, 96));
        [[UIColor colorWithWhite:0.95 alpha:1] setFill]; UIRectFill(CGRectMake(12, 12, 44, 44));
        [[UIColor colorWithWhite:0.10 alpha:1] setFill]; UIRectFill(CGRectMake(36, 36, 44, 44));
    }];
}

static void report(NSInteger rgb, UIImage *image) {
    SPTPlayerState *state = [SPTPlayerState new];
    if (rgb >= 0) {
        SPTPlayerTrack *track = [SPTPlayerTrack new];
        track.URI = [NSString stringWithFormat:@"spotify:track:%06lX", (long)rgb];
        if (image) {
            NSString *dir = SGLocalFileCoversDirectory();
            [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
            NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"fixture-%06lX.png", (long)rgb]];
            NSCAssert([UIImagePNGRepresentation(image) writeToFile:path atomically:YES], @"Fixture write failed");
            track.metadata = @{@"image_url": SGLocalFileCoverURL(path)};
        }
        state.track = track;
    }
    [[_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation new] player:nil stateDidChange:state];
}

static void reportLocal(UIImage *image) {
    SGLocalFileSaveEdit(localURI, @{}, nil, NO);
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    track.URI = localURI;
    track.metadata = @{@"image_small_url": image};
    SPTPlayerState *state = [SPTPlayerState new];
    state.track = track;
    [[_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation new] player:nil stateDidChange:state];
}

static BOOL closeTo(UIColor *a, UIColor *b) {
    CGFloat ar, ag, ab, br, bg, bb;
    return [a getRed:&ar green:&ag blue:&ab alpha:NULL] && [b getRed:&br green:&bg blue:&bb alpha:NULL] &&
        fabs(ar - br) < 0.005 && fabs(ag - bg) < 0.005 && fabs(ab - bb) < 0.005;
}

@interface Harness : UIResponder <UIApplicationDelegate>
@property (nonatomic) UIWindow *window;
@end

@implementation Harness {
    UIImageView *_cover;
    UILabel *_title;
    UIView *_gradientHost;
    UIButton *_button;
    BOOL _redesign, _enabled;
}

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    _redesign = SGRedesignedUI();
    _enabled = SGHidden(_redesign ? SGRKeyArtworkAccent : SGKeyArtworkAccent);
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *home = [_TtC19Home_FunkisPageImpl20FunkisViewController new];
    self.window.rootViewController = home;
    home.view.backgroundColor = UIColor.blackColor;
    CGRect bounds = self.window.bounds;
    UIViewController *feed = [_TtC16Home_EvoPageImpl33EvoLoadableResourceViewController new];
    [home addChildViewController:feed];
    UIView *page = feed.view;
    page.accessibilityIdentifier = @"HomePageView";
    page.frame = bounds;
    [home.view addSubview:page];
    [feed didMoveToParentViewController:home];
    UICollectionView *list = [[_TtC16Home_CarouselKit29TouchCancellingCollectionView alloc]
        initWithFrame:bounds collectionViewLayout:[UICollectionViewFlowLayout new]];
    list.backgroundColor = UIColor.clearColor;
    [page addSubview:list];
    _gradientHost = _redesign ? page : list;
    if (_redesign) {
        HomeHeaderElement *element = [[HomeHeaderElement alloc] initWithFrame:CGRectMake(0, 65, bounds.size.width, 56)];
        HomeHeaderView *header = [[HomeHeaderView alloc] initWithFrame:element.bounds];
        [header addSubview:[[UIStackView alloc] initWithFrame:CGRectInset(header.bounds, 16, 7)]];
        [element addSubview:header];
        [home.view addSubview:element];
        SGRHomeSetPageTint(color(0x172A2B));
    } else {
        UILabel *heading = [[UILabel alloc] initWithFrame:CGRectMake(20, 72, 200, 44)];
        heading.text = @"Home";
        heading.font = [UIFont boldSystemFontOfSize:32];
        [home.view addSubview:heading];
    }

    CGFloat width = bounds.size.width;
    _title = [[UILabel alloc] initWithFrame:CGRectMake(22, 148, width - 44, 48)];
    _title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _title.numberOfLines = 2;
    _title.text = [NSString stringWithFormat:@"%@ look · Album art accent %@", _redesign ? @"Redesigned" : @"Native", _enabled ? @"on" : @"off"];
    [home.view addSubview:_title];
    _cover = [[UIImageView alloc] initWithFrame:CGRectMake(22, 220, width - 44, width - 44)];
    [home.view addSubview:_cover];
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    _button.frame = CGRectMake(22, CGRectGetMaxY(_cover.frame) + 26, width - 44, 52);
    _button.backgroundColor = color(SGSpotifyGreen);
    _button.layer.cornerRadius = 26;
    [_button setTitle:@"▶  Now playing" forState:UIControlStateNormal];
    [_button setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [home.view addSubview:_button];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 700), dispatch_get_main_queue(), ^{
        [self runStep:0];
    });
    return YES;
}

- (void)runStep:(NSUInteger)step {
    const NSInteger fixtures[] = {red, blue, grey, -1, blue, red, blue, red};
    NSInteger fixture = fixtures[step];
    UIImage *image = fixture < 0 ? nil : cover(fixture);
    _cover.image = image;
    if (step == 1) report(red, cover(red));
    if (step == 4) report(fixture, nil);
    if (step == 5) reportLocal(image);
    else if (step == 6) SGLocalFileSaveEdit(localURI, @{}, image, YES);
    else if (step == 7) SGLocalFileSaveEdit(localURI, @{}, nil, NO);
    else report(fixture, image);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 450), dispatch_get_main_queue(), ^{
        [self verify:step fixture:fixture image:image];
        if (step < 7) [self runStep:step + 1];
        else {
            NSString *result = [NSString stringWithFormat:@"PASS %@ accent %@: track changes, late artwork, fallback and local cover edits",
                                self->_redesign ? @"redesigned" : @"native", self->_enabled ? @"on" : @"off"];
            NSLog(@"%@", result);
            [result writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.txt"]
                     atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
    });
}

- (void)verify:(NSUInteger)step fixture:(NSInteger)fixture image:(UIImage *)image {
    NSInteger sampled = SGArtworkAccentRGB(image);
    NSCAssert((sampled >= 0) == (fixture == red || fixture == blue), @"Unexpected palette for fixture %ld", (long)fixture);
    if (sampled >= 0) {
        NSInteger r = sampled >> 16, b = sampled & 0xFF;
        NSCAssert(fixture == red ? r > b : b > r, @"Wrong artwork hue");
    }
    NSInteger effective = _enabled && sampled >= 0 ? sampled : _redesign ? SGRDefaultAccent : SGSpotifyGreen;
    NSCAssert(closeTo(_button.backgroundColor, color(effective)), @"Existing control not repainted at step %lu", (unsigned long)step);
    NSCAssert(closeTo(color(SGSpotifyGreen), color(effective)), @"New color token wrong at step %lu", (unsigned long)step);
    CAGradientLayer *gradient;
    for (UIView *view in _gradientHost.subviews) {
        if ([view.layer isKindOfClass:CAGradientLayer.class]) gradient = (CAGradientLayer *)view.layer;
    }
    NSCAssert(gradient.colors.count >= 2, @"Home gradient missing");
    UIColor *top = [UIColor colorWithCGColor:(__bridge CGColorRef)gradient.colors.firstObject];
    NSInteger tint = _redesign ? 0x172A2B : 0x0B4110;
    if (_enabled && sampled >= 0) {
        CGFloat f = _redesign ? 0.25 : 0x41 / (255.0 * 0.96);
        tint = (lround((sampled >> 16) * f) << 16) | (lround(((sampled >> 8) & 0xFF) * f) << 8) | lround((sampled & 0xFF) * f);
    }
    NSCAssert(closeTo(top, color(tint)), @"Home tint wrong at step %lu: %@", (unsigned long)step, top);
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(Harness.class));
    }
}
