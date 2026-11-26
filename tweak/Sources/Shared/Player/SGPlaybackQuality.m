#import "SGPlaybackQuality.h"
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL getterReturns(id object, SEL selector, char encoding) {
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char type[2] = {0};
    method_getReturnType(method, type, sizeof(type));
    return type[0] == encoding;
}

NSString *SGPlaybackQualityText(SPTPlayerState *state) {
    SEL qualityGetter = sel_registerName("playbackQuality"), bitrateGetter = sel_registerName("bitrateLevel");
    if (!getterReturns(state, qualityGetter, '@')) return nil;
    id quality = ((id (*)(id, SEL))objc_msgSend)(state, qualityGetter);
    if (!getterReturns(quality, bitrateGetter, 'Q')) return nil;
    // SPTPlaybackQuality's stringToBitrateLevel: in Spotify 9.2.2.
    switch (((unsigned long long (*)(id, SEL))objc_msgSend)(quality, bitrateGetter)) {
        case 1: return @"Low";
        case 2: return @"Normal";
        case 3: return @"High";
        case 4: return @"Very high";
        case 5:
        case 6: return @"Lossless";
        default: return nil;
    }
}

@interface SGPlaybackQualityObserver : NSObject <SGPlayerStateObserver>
@property (nonatomic, weak) UIView *owner;
@property (nonatomic, copy) void (^update)(UIView *owner);
@end

@implementation SGPlaybackQualityObserver

- (void)refresh {
    UIView *owner = self.owner;
    if (owner.window) self.update(owner);
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    [self refresh];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {}

- (void)defaultsChanged {
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

@end

void SGObservePlaybackQuality(UIView *owner, void (^update)(UIView *owner)) {
    static char key;
    if (objc_getAssociatedObject(owner, &key)) return;
    SGPlaybackQualityObserver *observer = [SGPlaybackQualityObserver new];
    observer.owner = owner;
    observer.update = update;
    objc_setAssociatedObject(owner, &key, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGAddPlayerStateObserver(observer);
    [NSNotificationCenter.defaultCenter addObserver:observer selector:@selector(defaultsChanged)
                                               name:NSUserDefaultsDidChangeNotification object:nil];
}
