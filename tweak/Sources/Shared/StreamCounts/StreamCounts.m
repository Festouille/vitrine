#import "Core/SGCore.h"
#import "StreamCounts.h"

@interface SGStreamCountIdentity : NSObject
+ (NSString *)trackURIInView:(UIView *)view album:(BOOL)album;
+ (NSString *)trackURIForPlaylistIdentifier:(id)identifier;
@end

static BOOL isTrack(NSString *uri) {
    return [uri hasPrefix:@"spotify:track:"] && uri.length == 36 &&
        [uri rangeOfString:@"[^a-zA-Z0-9]" options:NSRegularExpressionSearch
                     range:NSMakeRange(14, 22)].location == NSNotFound;
}

NSString *SGStreamCountTrackURI(UIView *cell, BOOL album) {
    if (!album && [cell isKindOfClass:UICollectionViewCell.class]) {
        for (UIView *view = cell.superview; view; view = view.superview) {
            if (![view isKindOfClass:UICollectionView.class]) continue;
            UICollectionView *list = (UICollectionView *)view;
            id source = list.dataSource;
            NSIndexPath *path = [list indexPathForCell:(UICollectionViewCell *)cell];
            if (!path || ![source respondsToSelector:@selector(itemIdentifierForIndexPath:)]) break;
            id identifier = [source itemIdentifierForIndexPath:path];
            NSString *uri = identifier ? [SGStreamCountIdentity trackURIForPlaylistIdentifier:identifier] : nil;
            if (isTrack(uri)) return uri;
            break;
        }
    }
    __block NSString *track;
    SGForEachView(cell, ^(UIView *view) {
        if (track) return;
        NSString *uri = [SGStreamCountIdentity trackURIInView:view album:album];
        if (isTrack(uri)) track = uri;
    });
    if (track || !album) return track;
    static char kMenuKey;
    UIView *menu = SGFindIdentifier(cell, @"Components.UI.ContextMenuButton-", &kMenuKey);
    NSString *identifier = menu.accessibilityIdentifier;
    if (identifier.length > @"Components.UI.ContextMenuButton-".length) {
        NSString *uri = [@"spotify:track:" stringByAppendingString:[identifier substringFromIndex:@"Components.UI.ContextMenuButton-".length]];
        if (isTrack(uri)) return uri;
    }
    return nil;
}

static id field(id object, NSString *key) {
    return [object isKindOfClass:NSDictionary.class] ? object[key] : nil;
}

NSNumber *SGStreamCountInReply(NSData *reply, NSString *uri) {
    if (!isTrack(uri) || !reply.length || reply.length > 1024 * 1024) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:reply options:0 error:nil];
    id track = field(field(json, @"data"), @"trackUnion");
    id resultURI = field(track, @"uri");
    if (resultURI ? ![resultURI isEqual:uri] : ![field(track, @"id") isEqual:[uri substringFromIndex:14]]) return nil;
    id value = field(track, @"playcount");
    if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFNumberGetTypeID() &&
        !CFNumberIsFloatType((__bridge CFNumberRef)value)) value = [value stringValue];
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 19 ||
        [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound)
        return nil;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    unsigned long long number;
    return [scanner scanUnsignedLongLong:&number] && number <= LLONG_MAX ? @(number) : nil;
}

@interface SPTDataLoaderRequest : NSObject
- (instancetype)initWithURL:(NSURL *)url sourceIdentifier:(NSString *)source uniqueIdentifier:(int64_t)identifier;
- (void)setTimeout:(NSTimeInterval)timeout;
- (void)setShouldStopRedirection:(BOOL)stop;
- (void)setMethod:(NSInteger)method;
- (void)setBody:(NSData *)body;
- (void)addValue:(NSString *)value forHeader:(NSString *)header;
@end

@interface SPTDataLoaderResponse : NSObject
- (NSInteger)statusCode;
- (NSData *)body;
@end

@interface SPTDataLoaderBlockWrapper : NSObject
- (id)performRequest:(SPTDataLoaderRequest *)request completion:(void (^)(SPTDataLoaderResponse *, NSError *))completion;
@end

@interface SPTDataLoaderFactory : NSObject
- (BOOL)shouldAuthoriseRequest:(SPTDataLoaderRequest *)request;
- (SPTDataLoaderBlockWrapper *)createDataLoaderBlockWrapper;
@end

@interface SGStreamCountEntry : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSTimeInterval expires;
@end
@implementation SGStreamCountEntry
@end

static NSHashTable<SPTDataLoaderFactory *> *sg_factories;
static NSMutableDictionary<NSString *, SPTDataLoaderBlockWrapper *> *sg_loaders;
static NSCache<NSString *, SGStreamCountEntry *> *sg_counts;
static NSMutableDictionary<NSString *, NSMapTable<id, dispatch_block_t> *> *sg_waiters;
static NSMutableOrderedSet<NSString *> *sg_queue;
static NSUInteger sg_active;
static int64_t sg_identifier;
static NSTimeInterval sg_pausedUntil;

static NSTimeInterval now(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static void pump(void);

static void received(NSString *uri, NSNumber *count, NSInteger status) {
    [sg_loaders removeObjectForKey:uri];
    sg_active--;
    if (status == 401 || status == 403 || status == 429) sg_pausedUntil = now() + 120;
    SGStreamCountEntry *entry = [SGStreamCountEntry new];
    if (count) {
        NSNumberFormatter *format = [NSNumberFormatter new];
        format.numberStyle = NSNumberFormatterDecimalStyle;
        entry.text = [format stringFromNumber:count];
    }
    entry.expires = now() + (count ? 3600 : status == 200 ? 600 : 120);
    [sg_counts setObject:entry forKey:uri];
    NSMapTable *waiters = sg_waiters[uri];
    [sg_waiters removeObjectForKey:uri];
    for (dispatch_block_t waiter in waiters.objectEnumerator) waiter();
    pump();
}

static SPTDataLoaderRequest *makeRequest(NSString *uri) {
    static NSString *const kQueryHash = @"612585ae06ba435ad26369870deaae23b5c8800a256cd8a57e08eddc25a37294";
    static const NSInteger kDataLoaderPOST = 2;
    NSURL *url = [NSURL URLWithString:@"https://api-partner.spotify.com/pathfinder/v1/query"];
    Class cls = objc_getClass("SPTDataLoaderRequest");
    if (![cls instancesRespondToSelector:@selector(initWithURL:sourceIdentifier:uniqueIdentifier:)] ||
        ![cls instancesRespondToSelector:@selector(setTimeout:)] ||
        ![cls instancesRespondToSelector:@selector(setShouldStopRedirection:)] ||
        ![cls instancesRespondToSelector:@selector(setMethod:)] ||
        ![cls instancesRespondToSelector:@selector(setBody:)] ||
        ![cls instancesRespondToSelector:@selector(addValue:forHeader:)]) return nil;
    SPTDataLoaderRequest *request = [[cls alloc] initWithURL:url sourceIdentifier:@"Vitrine.StreamCounts"
                                           uniqueIdentifier:--sg_identifier];
    [request setTimeout:12];
    [request setShouldStopRedirection:YES];
    [request setMethod:kDataLoaderPOST];
    [request setBody:[NSJSONSerialization dataWithJSONObject:@{
        @"operationName": @"getTrack",
        @"variables": @{@"uri": uri},
        @"extensions": @{@"persistedQuery": @{@"version": @1, @"sha256Hash": kQueryHash}},
    } options:0 error:nil]];
    [request addValue:@"application/json" forHeader:@"Accept"];
    [request addValue:@"application/json" forHeader:@"Content-Type"];
    return request;
}

static void fetch(NSString *uri, SPTDataLoaderRequest *request, SPTDataLoaderBlockWrapper *loader) {
    sg_loaders[uri] = loader;
    sg_active++;
    [loader performRequest:request completion:^(SPTDataLoaderResponse *response, NSError *error) {
        NSInteger status = [response respondsToSelector:@selector(statusCode)] ? response.statusCode : 0;
        NSNumber *count = status == 200 && !error && [response respondsToSelector:@selector(body)] ?
            SGStreamCountInReply(response.body, uri) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ received(uri, count, status); });
    }];
}

static void pump(void) {
    if (sg_pausedUntil > now() || !SGHidden(SGKeyStreamCounts)) {
        for (NSString *uri in sg_queue) [sg_waiters removeObjectForKey:uri];
        [sg_queue removeAllObjects];
        return;
    }
    if (!sg_factories.count) return;
    while (sg_active < 4 && sg_queue.count) {
        NSString *uri = sg_queue.firstObject;
        if (!sg_waiters[uri].count) {
            [sg_queue removeObjectAtIndex:0];
            [sg_waiters removeObjectForKey:uri];
            continue;
        }
        SPTDataLoaderRequest *request = makeRequest(uri);
        if (!request) return;
        SPTDataLoaderBlockWrapper *loader = nil;
        for (SPTDataLoaderFactory *factory in sg_factories) {
            if (![factory shouldAuthoriseRequest:request]) continue;
            loader = [factory createDataLoaderBlockWrapper];
            if ([loader respondsToSelector:@selector(performRequest:completion:)]) break;
            loader = nil;
        }
        if (!loader) return;
        [sg_queue removeObjectAtIndex:0];
        fetch(uri, request, loader);
    }
}

void SGStreamCountRememberDataLoader(id factory) {
    if (![factory respondsToSelector:@selector(createDataLoaderBlockWrapper)] ||
        ![factory respondsToSelector:@selector(shouldAuthoriseRequest:)]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sg_factories) sg_factories = [NSHashTable weakObjectsHashTable];
        [sg_factories addObject:factory];
        pump();
    });
}

NSString *SGStreamCountText(NSString *uri, id observer, dispatch_block_t changed) {
    if (!SGHidden(SGKeyStreamCounts) || !isTrack(uri)) return nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_loaders = [NSMutableDictionary dictionary];
        sg_counts = [NSCache new];
        sg_counts.countLimit = 2048;
        sg_waiters = [NSMutableDictionary dictionary];
        sg_queue = [NSMutableOrderedSet orderedSet];
    });
    SGStreamCountEntry *entry = [sg_counts objectForKey:uri];
    if (entry.expires > now()) return entry.text;
    if (sg_pausedUntil > now()) return nil;
    NSMapTable *waiters = sg_waiters[uri];
    if (!waiters) {
        if (sg_queue.count >= 96) return nil;
        sg_waiters[uri] = waiters = [NSMapTable weakToStrongObjectsMapTable];
        [sg_queue addObject:uri];
    }
    [waiters setObject:[changed copy] forKey:observer];
    pump();
    return nil;
}
