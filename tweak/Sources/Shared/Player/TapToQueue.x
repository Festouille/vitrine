#import "Core/SGCore.h"
#import "QueueHelpers.h"

@interface SPTPlayerTrack (SGTapToQueue)
- (instancetype)initWithURI:(NSURL *)uri albumURI:(NSURL *)album artistURI:(NSURL *)artist andUID:(NSString *)uid;
@end

@interface SPTask : NSObject
- (id)addCallback:(void (^)(id))callback on:(dispatch_queue_t)queue;
- (id)addErrorCallback:(void (^)(NSError *))callback on:(dispatch_queue_t)queue;
@end

@interface SPTPlayerQueueWrapperImpl : NSObject
- (instancetype)initWithPlayer:(id)player;
- (SPTask *)queueTrack:(SPTPlayerTrack *)track;
@end

static NSString *const kMenuPrefix = @"Components.UI.ContextMenuButton-";
static char kTapKey, kRowKey, kMenuKey, kPlaylistTitleKey;

static UIView *songRow(UICollectionViewCell *cell) {
    if ([cell.accessibilityIdentifier isEqualToString:@"Playlist.ItemCell"] &&
        SGFindIdentifier(cell.contentView, @"Track.Row.Content.Title", &kPlaylistTitleKey)) {
        return SGFindIdentifier(cell.contentView, @"Encore.ListRow", &kRowKey);
    }
    return SGFindIdentifier(cell.contentView, @"Components.UI.RetrievalRowElementUI", &kRowKey);
}

static NSURL *trackURI(UICollectionViewCell *cell) {
    UIView *row = songRow(cell);
    if (!row) return nil;
    UIView *menu = SGFindIdentifier(row, kMenuPrefix, &kMenuKey);
    NSString *identifier = menu.accessibilityIdentifier;
    if (identifier.length != kMenuPrefix.length + 22) return nil;
    NSString *trackID = [identifier substringFromIndex:kMenuPrefix.length];
    if ([trackID rangeOfString:@"[^a-zA-Z0-9]" options:NSRegularExpressionSearch].location != NSNotFound) return nil;
    return [NSURL URLWithString:[@"spotify:track:" stringByAppendingString:trackID]];
}

static BOOL canQueue(void) {
    return SGPlayer() &&
        [NSClassFromString(@"SPTPlayerQueueWrapperImpl") instancesRespondToSelector:@selector(initWithPlayer:)] &&
        [NSClassFromString(@"SPTPlayerQueueWrapperImpl") instancesRespondToSelector:@selector(queueTrack:)] &&
        [NSClassFromString(@"SPTPlayerTrack") instancesRespondToSelector:@selector(initWithURI:albumURI:artistURI:andUID:)];
}

static BOOL queueSong(UICollectionViewCell *cell) {
    NSURL *uri = trackURI(cell);
    if (!uri || !canQueue()) return NO;
    Class trackClass = NSClassFromString(@"SPTPlayerTrack"), wrapperClass = NSClassFromString(@"SPTPlayerQueueWrapperImpl");
    SPTPlayerTrack *track = [[trackClass alloc] initWithURI:uri albumURI:nil artistURI:nil andUID:nil];
    if (!track) return NO;
    SPTPlayerQueueWrapperImpl *wrapper = [[wrapperClass alloc] initWithPlayer:SGPlayer()];
    if (!wrapper) return NO;
    SPTask *result = [wrapper queueTrack:track];
    if ([result respondsToSelector:@selector(addCallback:on:)]) {
        [result addCallback:^(id value) {
            [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"Added to queue");
        } on:dispatch_get_main_queue()];
    }
    if ([result respondsToSelector:@selector(addErrorCallback:on:)]) {
        [result addErrorCallback:^(NSError *error) {
            [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeError];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"Couldn’t add to queue");
        } on:dispatch_get_main_queue()];
    }
    return YES;
}

@interface SGQueueSongTap : UITapGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UICollectionViewCell *cell;
@end

@implementation SGQueueSongTap
- (instancetype)initWithCell:(UICollectionViewCell *)cell {
    if ((self = [super initWithTarget:nil action:NULL])) {
        self.cell = cell;
        self.delegate = self;
        self.cancelsTouchesInView = YES;
        [self addTarget:self action:@selector(addSong)];
    }
    return self;
}
- (void)addSong {
    if (self.state == UIGestureRecognizerStateRecognized) queueSong(self.cell);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    UIView *row = songRow(self.cell);
    if (!row || !canQueue() || ![touch.view isDescendantOfView:row]) return NO;
    for (UIView *view = touch.view; view && view != row; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || [view.accessibilityIdentifier hasPrefix:kMenuPrefix]) return NO;
    }
    return trackURI(self.cell) != nil;
}
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    return ![other isKindOfClass:UITapGestureRecognizer.class] && [super canBePreventedByGestureRecognizer:other];
}
@end

static void attachSongTap(UICollectionViewCell *cell) {
    if (objc_getAssociatedObject(cell, &kTapKey) || !trackURI(cell)) return;
    SGQueueSongTap *tap = [[SGQueueSongTap alloc] initWithCell:cell];
    [cell addGestureRecognizer:tap];
    objc_setAssociatedObject(cell, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    attachSongTap((UICollectionViewCell *)self);
}
- (BOOL)accessibilityActivate {
    return queueSong((UICollectionViewCell *)self) || %orig;
}
%end

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (void)layoutSubviews {
    %orig;
    attachSongTap((UICollectionViewCell *)self);
}
- (BOOL)accessibilityActivate {
    return queueSong((UICollectionViewCell *)self) || %orig;
}
%end

%ctor {
    if (SGFlag(SGKeyTapToQueue, NO)) %init;
}
