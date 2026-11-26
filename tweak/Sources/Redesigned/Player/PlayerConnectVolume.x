// SPDX-License-Identifier: GPL-3.0-only
// Adapted from MVTTSUN/glassify (9b72b51) and jadetheda/compiling-vitrine-pls-ignore (f68c807c).
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Player.h"
#import "PlayerConnectVolume.h"

@protocol SGRConnectVolumeAPI
- (double)connectVolume;
- (void)add:(id)observer;
- (void)remove:(id)observer;
- (BOOL)setVolume:(double)value assumingPreviousVolume:(double)previous reason:(NSString *)reason;
- (void)setVolume:(double)value reason:(NSString *)reason;
@end

@protocol SGRConnectEntity
- (BOOL)isVolumeSupported;
- (NSString *)connectStateIdentifier;
@end

@protocol SGRConnectAggregator
- (BOOL)isPlayingRemotely;
- (id<SGRConnectEntity>)activeConnectEntity;
- (void)addStateObserver:(id)observer;
- (void)removeStateObserver:(id)observer;
@end

NSString *const SGRConnectVolumeDidChangeNotification = @"SGRConnectVolumeDidChangeNotification";
static NSString *const kReason = @"VitrinePlayerVolume";
static const NSTimeInterval kSendInterval = 0.12, kSettleTime = 0.6;

static __weak id sg_seenVolume, sg_seenAggregator;
static __weak NSObject<SGRConnectVolumeAPI> *sg_volume;
static __weak NSObject<SGRConnectAggregator> *sg_aggregator;
static __weak UIControl *sg_visibleRow;
static NSString *sg_route;
static NSString *sg_lastSentRoute;
static BOOL sg_hydrated;
static NSUInteger sg_revision;
static double sg_target, sg_lastSent;
static CFTimeInterval sg_lastSend;

BOOL SGRPlayerConnectVolumeOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGRedesignedUI() && SGRPlayerVolumeOn() && SGFlag(SGRKeyPlayerConnectVolume, NO); });
    return on;
}

static NSString *activeRoute(void) {
    NSObject<SGRConnectAggregator> *aggregator = sg_aggregator;
    NSObject<SGRConnectVolumeAPI> *volume = sg_volume;
    if (![volume respondsToSelector:@selector(connectVolume)] ||
        (![volume respondsToSelector:@selector(setVolume:assumingPreviousVolume:reason:)] &&
         ![volume respondsToSelector:@selector(setVolume:reason:)]) ||
        ![aggregator respondsToSelector:@selector(isPlayingRemotely)] || ![aggregator isPlayingRemotely] ||
        ![aggregator respondsToSelector:@selector(activeConnectEntity)]) return nil;
    NSObject<SGRConnectEntity> *entity = (id)[aggregator activeConnectEntity];
    if (![entity respondsToSelector:@selector(isVolumeSupported)] || ![entity isVolumeSupported] ||
        ![entity respondsToSelector:@selector(connectStateIdentifier)]) return nil;
    NSString *identifier = [entity connectStateIdentifier];
    return identifier.length ? identifier : nil;
}

static NSString *updateRoute(void) {
    NSString *route = activeRoute();
    if (sg_route != route && ![sg_route isEqualToString:route]) {
        sg_route = [route copy];
        sg_hydrated = NO;
        ++sg_revision;
    }
    return sg_route;
}

NSString *SGRConnectVolumeRoute(double *value) {
    NSString *route = updateRoute();
    if (!route) return nil;
    double volume = [sg_volume connectVolume];
    if (!isfinite(volume) || volume < 0 || volume > 1) return nil;
    // A new route can report an uninitialized zero until it has received its first volume.
    if (volume == 0 && !sg_hydrated) return nil;
    sg_hydrated = YES;
    if (value) *value = volume;
    return route;
}

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRConnectVolumeDidChangeNotification object:nil];
}

@interface SGRConnectVolumeObserver : NSObject
@end

@implementation SGRConnectVolumeObserver
- (void)connectVolumeDidChangeToValue:(double)value {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (updateRoute() && isfinite(value) && value >= 0 && value <= 1 && [sg_volume connectVolume] == value) {
            sg_hydrated = YES;
        }
        changed();
    });
}

- (void)remoteMediaSessionVolumeDidChangeToValue:(double)value {
    dispatch_async(dispatch_get_main_queue(), ^{ changed(); });
}

- (void)groupedDeviceVolumeDidChangeToValue:(double)value groupDeviceIdentifier:(NSString *)identifier {
    dispatch_async(dispatch_get_main_queue(), ^{ changed(); });
}

- (void)aggregator:(id)aggregator didUpdateAggregatorState:(id)state {
    dispatch_async(dispatch_get_main_queue(), ^{ changed(); });
}
@end

static SGRConnectVolumeObserver *observer(void) {
    static SGRConnectVolumeObserver *observer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = SGRConnectVolumeObserver.class;
        for (NSString *name in @[@"SPTConnectVolumeObserver", @"SPTConnectAggregatorStateObserver"]) {
            Protocol *protocol = objc_getProtocol(name.UTF8String);
            if (protocol) class_addProtocol(cls, protocol);
        }
        observer = [cls new];
    });
    return observer;
}

static void remember(id object, BOOL isVolume) {
    @synchronized (SGRConnectVolumeObserver.class) {
        if (isVolume ? sg_seenVolume == object : sg_seenAggregator == object) return;
        if (isVolume) sg_seenVolume = object;
        else sg_seenAggregator = object;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (isVolume) {
                if ([sg_volume respondsToSelector:@selector(remove:)]) [sg_volume remove:observer()];
                sg_volume = object;
                if ([sg_volume respondsToSelector:@selector(add:)]) [sg_volume add:observer()];
            } else {
                if ([sg_aggregator respondsToSelector:@selector(removeStateObserver:)]) [sg_aggregator removeStateObserver:observer()];
                sg_aggregator = object;
                if ([sg_aggregator respondsToSelector:@selector(addStateObserver:)]) [sg_aggregator addStateObserver:observer()];
            }
            sg_route = nil;
            sg_hydrated = NO;
            ++sg_revision;
            changed();
        });
    }
}

static void send(NSString *route, BOOL retry) {
    double previous;
    if (![SGRConnectVolumeRoute(&previous) isEqualToString:route] || (retry && fabs(previous - sg_target) < 0.01)) return;
    NSObject<SGRConnectVolumeAPI> *volume = sg_volume;
    sg_lastSend = CACurrentMediaTime();
    sg_lastSent = sg_target;
    sg_lastSentRoute = route;
    if ([volume respondsToSelector:@selector(setVolume:assumingPreviousVolume:reason:)]) {
        [volume setVolume:sg_target assumingPreviousVolume:previous reason:kReason];
    } else if ([volume respondsToSelector:@selector(setVolume:reason:)]) {
        [volume setVolume:sg_target reason:kReason];
    }
}

BOOL SGRConnectSetVolume(NSString *route, double value, BOOL final) {
    if (![SGRConnectVolumeRoute(NULL) isEqualToString:route]) return NO;
    sg_target = MIN(1, MAX(0, value));
    NSUInteger revision = ++sg_revision;
    // Keep one trailing value even if the user stops moving before the throttle interval ends.
    NSTimeInterval delay = MAX(0, kSendInterval - (CACurrentMediaTime() - sg_lastSend));
    if (delay == 0) send(route, NO);
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_revision == revision) send(route, NO);
    });
    if (final) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay + kSettleTime) * NSEC_PER_SEC)),
                              dispatch_get_main_queue(), ^{
        if (sg_revision == revision) send(route, YES);
    });
    return YES;
}

void SGRConnectVolumeRowVisible(UIControl *row, BOOL visible) {
    if (visible) sg_visibleRow = row;
    else if (sg_visibleRow == row) sg_visibleRow = nil;
}

static BOOL rowHandledVolume(double value) {
    if (!NSThread.isMainThread || !sg_visibleRow.window || sg_visibleRow.alpha < 0.01 ||
        CACurrentMediaTime() - sg_lastSend >= kSettleTime || fabs(sg_lastSent - value) >= 0.01) return NO;
    return [SGRConnectVolumeRoute(NULL) isEqualToString:sg_lastSentRoute];
}

%group ConnectVolume
%hook _TtC18Connect_VolumeImpl10VolumeImpl
- (void)add:(id)observer {
    %orig;
    remember(self, YES);
}
- (double)connectVolume {
    remember(self, YES);
    return %orig;
}
%end

%hook _TtC22Connect_AggregatorImpl24ConnectAggregatorManager
- (void)addStateObserver:(id)observer {
    %orig;
    remember(self, NO);
}
- (BOOL)isPlayingRemotely {
    remember(self, NO);
    return %orig;
}
%end
%end

%group ConnectVolumePopup
%hook _TtC20Connect_VolumeUXImpl27RemoteVolumePopupController
- (void)remoteMediaSessionVolumeDidChangeToValue:(double)value {
    if (rowHandledVolume(value)) return;
    %orig;
}
%end
%end

%ctor {
    if (!SGRedesignedUI() || !SGRPlayerConnectVolumeOn()) return;
    Class volume = NSClassFromString(@"_TtC18Connect_VolumeImpl10VolumeImpl");
    Class aggregator = NSClassFromString(@"_TtC22Connect_AggregatorImpl24ConnectAggregatorManager");
    if (!class_getInstanceMethod(volume, @selector(add:)) ||
        !class_getInstanceMethod(volume, @selector(connectVolume)) ||
        !class_getInstanceMethod(aggregator, @selector(addStateObserver:)) ||
        !class_getInstanceMethod(aggregator, @selector(isPlayingRemotely))) return;
    %init(ConnectVolume);
    Class popup = NSClassFromString(@"_TtC20Connect_VolumeUXImpl27RemoteVolumePopupController");
    if (class_getInstanceMethod(popup, @selector(remoteMediaSessionVolumeDidChangeToValue:))) %init(ConnectVolumePopup);
}
