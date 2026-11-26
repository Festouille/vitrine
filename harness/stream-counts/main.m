#import "Core/SGCore.h"
#import "Shared/StreamCounts/StreamCounts.h"

@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell
@end
@implementation _TtC12Element_List18CollectionViewCell
@end
@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell : UICollectionViewCell
@end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
@end
@interface MockRetrievalListStructuredDataView : UIView
@end
@implementation MockRetrievalListStructuredDataView
@end
@interface SGStreamFixtureElementView : UIView
- (void)setTrackURI:(NSString *)uri;
@end

static NSString *const albumTrack = @"spotify:track:1AAAAAAAAAAAAAAAAAAAAA";
static NSString *const playlistTrack = @"spotify:track:2BBBBBBBBBBBBBBBBBBBBB";
static NSString *const noCount = @"spotify:track:3CCCCCCCCCCCCCCCCCCCCC";
static NSMutableDictionary<NSString *, NSNumber *> *requests;

UIColor *SGRAccentColor(void) { return nil; }

@interface SPTDataLoaderRequest : NSObject
@property NSURL *URL;
@property NSTimeInterval timeout;
@property BOOL shouldStopRedirection;
@property NSInteger method;
@property NSData *body;
@end
@implementation SPTDataLoaderRequest
- (instancetype)initWithURL:(NSURL *)url sourceIdentifier:(NSString *)source uniqueIdentifier:(int64_t)identifier {
    if ((self = [super init])) _URL = url;
    return self;
}
- (void)addValue:(NSString *)value forHeader:(NSString *)header {}
@end

@interface SPTDataLoaderResponse : NSObject
@property NSInteger statusCode;
@property NSData *body;
@end
@implementation SPTDataLoaderResponse
@end

@interface SPTDataLoaderBlockWrapper : NSObject
@end
@implementation SPTDataLoaderBlockWrapper
- (id)performRequest:(SPTDataLoaderRequest *)request completion:(void (^)(SPTDataLoaderResponse *, NSError *))completion {
    NSURL *url = request.URL;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:request.body options:0 error:nil];
    NSString *uri = json[@"variables"][@"uri"];
    NSCAssert([url.host isEqualToString:@"api-partner.spotify.com"] && [url.path isEqualToString:@"/pathfinder/v1/query"] &&
              request.method == 2 && [json[@"operationName"] isEqual:@"getTrack"] &&
              [json[@"extensions"][@"persistedQuery"][@"sha256Hash"] length] == 64 && request.shouldStopRedirection,
              @"unexpected request: %@", url);
    requests[uri] = @(requests[uri].unsignedIntegerValue + 1);
    NSMutableDictionary *track = [@{@"uri": uri} mutableCopy];
    if ([uri isEqual:albumTrack]) track[@"playcount"] = @"1234567";
    if ([uri isEqual:playlistTrack]) track[@"playcount"] = @84576;
    SPTDataLoaderResponse *reply = [SPTDataLoaderResponse new];
    reply.statusCode = 200;
    reply.body = [NSJSONSerialization dataWithJSONObject:@{@"data": @{@"trackUnion": track}} options:0 error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(reply, nil); });
    return nil;
}
@end

@interface SPTDataLoaderFactory : NSObject
@property BOOL authorized;
@end
@implementation SPTDataLoaderFactory
- (BOOL)shouldAuthoriseRequest:(SPTDataLoaderRequest *)request { return self.authorized; }
- (SPTDataLoaderBlockWrapper *)createDataLoaderBlockWrapper {
    NSCAssert(self.authorized, @"unauthorized factory selected");
    return [SPTDataLoaderBlockWrapper new];
}
@end

@interface SPTDataLoaderService : NSObject
- (SPTDataLoaderFactory *)createDataLoaderFactoryWithAuthorisers:(NSArray *)authorisers;
@end
@implementation SPTDataLoaderService
- (SPTDataLoaderFactory *)createDataLoaderFactoryWithAuthorisers:(NSArray *)authorisers {
    SPTDataLoaderFactory *factory = [SPTDataLoaderFactory new];
    factory.authorized = [authorisers containsObject:@"allowed"];
    return factory;
}
@end

static UILabel *label(UIView *view, CGRect frame, NSString *text, CGFloat size, UIColor *color) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size];
    label.textColor = color;
    [view addSubview:label];
    return label;
}

static UILabel *track(UIView *list, CGFloat y, NSString *title, NSString *artist, NSString *uri, BOOL album) {
    CGFloat width = list.bounds.size.width;
    Class cls = album ? _TtC12Element_List18CollectionViewCell.class :
        _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class;
    UICollectionViewCell *cell = [[cls alloc] initWithFrame:CGRectMake(0, y, width, 64)];
    [list addSubview:cell];
    UIView *content;
    if (album) {
        content = [[MockRetrievalListStructuredDataView alloc] initWithFrame:cell.bounds];
        UIButton *menu = [[UIButton alloc] initWithFrame:CGRectMake(width - 46, 4, 44, 52)];
        [menu setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
        menu.accessibilityIdentifier = [@"Components.UI.ContextMenuButton-" stringByAppendingString:[uri substringFromIndex:14]];
        menu.tintColor = UIColor.secondaryLabelColor;
        [content addSubview:menu];
    } else {
        SGStreamFixtureElementView *element = [[SGStreamFixtureElementView alloc] initWithFrame:cell.bounds];
        [element setTrackURI:uri];
        content = element;
    }
    [cell.contentView addSubview:content];
    CGFloat x = album ? 18 : 72;
    if (!album) {
        UIImageView *art = [[UIImageView alloc] initWithFrame:CGRectMake(16, 8, 46, 46)];
        art.contentMode = UIViewContentModeCenter;
        art.image = [UIImage systemImageNamed:@"music.note"];
        art.tintColor = UIColor.whiteColor;
        art.backgroundColor = [UIColor colorWithRed:0.32 green:0.20 blue:0.4 alpha:1];
        art.layer.cornerRadius = SGRedesignedUI() ? 6 : 0;
        [content addSubview:art];
    }
    label(content, CGRectMake(x, 8, width - x - 48, 24), title, 17, UIColor.whiteColor);
    UILabel *subtitle = label(content, CGRectMake(x, 32, width - x - 48, 20), artist, 14, UIColor.secondaryLabelColor);
    subtitle.accessibilityIdentifier = album ? @"EncoreConsumerMobile.View.Granular.Subtitle" : @"TrackRowElement.Subtitle";
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(x, 63, width - x - 16, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    if (SGRedesignedUI()) [content addSubview:line];
    return subtitle;
}

static void checkSameSizeReuse(UILabel *subtitle, NSString *artist, NSString *count, BOOL on) {
    UIView *view = subtitle.superview;
    while (view && ![view isKindOfClass:UICollectionViewCell.class]) view = view.superview;
    UICollectionViewCell *cell = (UICollectionViewCell *)view;
    NSCAssert(cell, @"fixture subtitle has no cell");
    [cell layoutIfNeeded];
    CGSize size = cell.bounds.size;
    [cell prepareForReuse];
    NSCAssert([subtitle.text isEqualToString:artist], @"reuse did not restore the artist subtitle");
    [cell layoutIfNeeded];
    NSCAssert(CGSizeEqualToSize(size, cell.bounds.size) && [subtitle.text containsString:count] == on,
              @"same-size reuse did not restore the cached count: %@", subtitle.text);
}

@interface SGStreamFixtureApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) NSArray *factories;
@end
@implementation SGStreamFixtureApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    BOOL on = SGHidden(SGKeyStreamCounts);
    SPTDataLoaderService *service = [SPTDataLoaderService new];
    self.factories = @[[service createDataLoaderFactoryWithAuthorisers:@[@"denied"]],
                       [service createDataLoaderFactoryWithAuthorisers:@[@"allowed"]]];
    CGRect bounds = UIScreen.mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:bounds];
    UIViewController *controller = [UIViewController new];
    self.window.rootViewController = controller;
    UIView *page = controller.view;
    page.backgroundColor = SGRedesignedUI() ? UIColor.blackColor : [UIColor colorWithWhite:0.07 alpha:1];
    CGFloat width = bounds.size.width;
    label(page, CGRectMake(16, 75, width - 32, 32), SGRedesignedUI() ? @"Redesigned" : @"Native", 24, UIColor.whiteColor);
    label(page, CGRectMake(16, 114, width - 32, 25), on ? @"Stream counts: On" : @"Stream counts: Off", 16, UIColor.secondaryLabelColor);
    label(page, CGRectMake(16, 195, width - 32, 28), @"Album", 22, UIColor.whiteColor);
    UILabel *album = track(page, 232, @"Break of Day", @"The Satellites", albumTrack, YES);
    UILabel *missing = track(page, 296, @"A Song Without a Count", @"The Satellites", noCount, YES);
    label(page, CGRectMake(16, 394, width - 32, 28), @"Playlist", 22, UIColor.whiteColor);
    UILabel *playlist = track(page, 433, @"Second Light", @"Low Tide", playlistTrack, NO);
    UILabel *duplicate = track(page, 497, @"Break of Day", @"The Satellites", albumTrack, NO);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSNumberFormatter *format = [NSNumberFormatter new];
        format.numberStyle = NSNumberFormatterDecimalStyle;
        NSString *first = [format stringFromNumber:@1234567];
        NSString *second = [format stringFromNumber:@84576];
        NSCAssert([album.text containsString:first] == on && [duplicate.text containsString:first] == on &&
                  [playlist.text containsString:second] == on && [missing.text isEqualToString:@"The Satellites"],
                  @"unexpected row subtitles: %@ / %@ / %@ / %@", album.text, missing.text, playlist.text, duplicate.text);
        checkSameSizeReuse(album, @"The Satellites", first, on);
        checkSameSizeReuse(playlist, @"Low Tide", second, on);
        NSCAssert(requests.count == (on ? 3 : 0) && (!on || requests[albumTrack].intValue == 1),
                  @"requests should be deduplicated and disabled when off: %@", requests);
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.txt"];
        NSString *result = [NSString stringWithFormat:@"%@ %@: row counts, missing counts and request deduplication held",
            SGRedesignedUI() ? @"Redesigned" : @"Native", on ? @"on" : @"off"];
        [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"%@", result);
    });
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        requests = [NSMutableDictionary dictionary];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGStreamFixtureApp.class));
    }
}
