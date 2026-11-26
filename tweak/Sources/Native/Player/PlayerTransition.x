#import "Core/SGCore.h"
#import "NowPlaying.h"

@interface SPTBarOverlayPresentationTransition : NSObject
- (id<UIViewControllerContextTransitioning>)transitioningContext;
- (UIView *)overlayView;
- (UIView *)barSnapshotView;
- (double)progress;
@end

static CGFloat sg_transitionBlend(CGFloat progress) {
    CGFloat t = MIN(1, MAX(0, progress / 0.85));
    return t * t * (3 - 2 * t);
}

%group SGNativeLegacyTransition
%hook SPTBarOverlayPresentationTransition
- (void)setProgress:(double)progress {
    %orig;
    if (!SGFlag(SGKeyPlayerAMPolish, NO) || UIAccessibilityIsReduceMotionEnabled()) return;
    UIView *container = [self transitioningContext].containerView;
    UIView *player = [self overlayView], *bar = [self barSnapshotView];
    if (!container || !player || !bar || player.superview != container || bar.superview != container ||
        container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return;

    CGFloat blend = sg_transitionBlend([self progress]);
    [UIView performWithoutAnimation:^{
        player.alpha = blend;
        bar.alpha = 1 - blend;
    }];
}
%end
%end

static NSString *const kSGTransitionOpacity = @"sg.compactTransitionOpacity";
static char kSGTransitionFollower;

// A presentation-only override: the stock property animator still owns its opacity and its
// completion. Removing this animation reveals its unmodified result, including on cancellation.
static void sg_showOpacity(CALayer *layer, CGFloat opacity) {
    CABasicAnimation *opacityOverride = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacityOverride.fromValue = @(opacity);
    opacityOverride.toValue = @(opacity);
    opacityOverride.duration = 1;
    opacityOverride.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - 0.1;
    [layer removeAnimationForKey:kSGTransitionOpacity];
    [layer addAnimation:opacityOverride forKey:kSGTransitionOpacity];
}

@interface SGCompactTransitionFollower : NSObject
@property (nonatomic, weak) id animator;
@property (nonatomic, weak) id<UIViewControllerContextTransitioning> context;
@property (nonatomic, weak) UIView *player, *bar, *container;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CGFloat openY, restY, lastY;
@property (nonatomic) NSInteger still;
@property (nonatomic) CFTimeInterval lastMove;
- (void)tick:(CADisplayLink *)link;
- (void)finish;
@end

@implementation SGCompactTransitionFollower

- (void)tick:(CADisplayLink *)link {
    UIView *player = self.player, *bar = self.bar, *container = self.container;
    id<UIViewControllerContextTransitioning> context = self.context;
    if (!self.animator || !context || !container.window || !player || !bar ||
        player.superview != container || bar.superview != container ||
        UIAccessibilityIsReduceMotionEnabled() || !SGFlag(SGKeyPlayerAMPolish, NO)) {
        [self finish];
        return;
    }

    CALayer *drawn = player.layer.presentationLayer;
    CGFloat y = drawn.frame.origin.y;
    BOOL hasFrame = drawn && isfinite(y);
    BOOL moved = hasFrame && fabs(y - self.lastY) > 0.5;
    NSArray *keys = player.layer.animationKeys;
    BOOL moving = keys.count > ([keys containsObject:kSGTransitionOpacity] ? 1u : 0u);
    BOOL interactive = context.isInteractive;
    self.still = moved || moving || interactive ? 0 : self.still + 1;
    if (moved || interactive) self.lastMove = link.timestamp;
    if (self.still >= 3 || (!interactive && link.timestamp - self.lastMove > 0.9)) {
        [self finish];
        return;
    }
    if (!hasFrame) return;
    CGFloat blend = sg_transitionBlend((self.restY - y) / (self.restY - self.openY));
    sg_showOpacity(player.layer, blend);
    sg_showOpacity(bar.layer, 1 - blend);
    self.lastY = y;
}

- (void)finish {
    [self.link invalidate];
    self.link = nil;
    [self.player.layer removeAnimationForKey:kSGTransitionOpacity];
    [self.bar.layer removeAnimationForKey:kSGTransitionOpacity];
}

@end

static CGFloat sg_compactRestY(id animator) {
    Class cls = object_getClass(animator);
    Ivar ivar = class_getInstanceVariable(cls, "npbFrame");
    if (!ivar) return NAN;
    const char *type = ivar_getTypeEncoding(ivar);
    ptrdiff_t offset = ivar_getOffset(ivar);
    if ((type && *type && strncmp(type, "{CGRect", 7) != 0) || offset < 0 ||
        (size_t)offset + sizeof(CGRect) > class_getInstanceSize(cls)) return NAN;
    CGRect frame;
    memcpy(&frame, (const char *)(__bridge void *)animator + offset, sizeof(frame));
    return CGRectIsEmpty(frame) ? NAN : CGRectGetMinY(frame);
}

static void sg_followCompactTransition(id animator, id<UIViewControllerContextTransitioning> context) {
    [objc_getAssociatedObject(animator, &kSGTransitionFollower) finish];
    if (!SGFlag(SGKeyPlayerAMPolish, NO) || UIAccessibilityIsReduceMotionEnabled() || !context) return;
    UIView *container = context.containerView;
    if (!container.window || container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return;
    UIViewController *to = [context viewControllerForKey:UITransitionContextToViewControllerKey];
    BOOL opening = to.isBeingPresented;
    UIView *player = [context viewForKey:opening ? UITransitionContextToViewKey : UITransitionContextFromViewKey];
    Ivar snapshot = class_getInstanceVariable(object_getClass(animator), "npbSnapshotView");
    UIView *bar = snapshot ? object_getIvar(animator, snapshot) : nil;
    if (![bar isKindOfClass:UIView.class] || !player || player == bar ||
        player.superview != container || bar.superview != container) return;
    CGFloat openY = CGRectGetMinY(container.bounds);
    CGFloat restY = sg_compactRestY(animator);
    if (!isfinite(restY) || restY <= openY || restY > CGRectGetMaxY(container.bounds)) return;

    SGCompactTransitionFollower *follower = [SGCompactTransitionFollower new];
    follower.animator = animator;
    follower.context = context;
    follower.container = container;
    follower.player = player;
    follower.bar = bar;
    follower.openY = openY;
    follower.restY = restY;
    follower.lastY = CGFLOAT_MAX;
    follower.lastMove = CACurrentMediaTime();
    follower.link = [CADisplayLink displayLinkWithTarget:follower selector:@selector(tick:)];
    follower.link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [follower.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(animator, &kSGTransitionFollower, follower, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%group SGNativeCompactTransition
%hook _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    %orig;
    sg_followCompactTransition(self, context);
}
- (void)startInteractiveTransition:(id<UIViewControllerContextTransitioning>)context {
    %orig;
    sg_followCompactTransition(self, context);
}
%end
%end

%ctor {
    if (!SGNativeUI()) return;
    Class animator = NSClassFromString(@"SPTBarOverlayPresentationTransition");
    if (animator) {
        if (class_getInstanceMethod(animator, @selector(setProgress:)) &&
            class_getInstanceMethod(animator, @selector(progress)) &&
            class_getInstanceMethod(animator, @selector(transitioningContext)) &&
            class_getInstanceMethod(animator, @selector(overlayView)) &&
            class_getInstanceMethod(animator, @selector(barSnapshotView))) %init(SGNativeLegacyTransition);
        return;
    }
    Class compact = NSClassFromString(@"_TtC19MainUI_TabBarUIImpl24CompactOverlayTransition");
    if (!class_getInstanceMethod(compact, @selector(animateTransition:)) ||
        !class_getInstanceMethod(compact, @selector(startInteractiveTransition:)) ||
        !class_getInstanceVariable(compact, "npbSnapshotView") ||
        !class_getInstanceVariable(compact, "npbFrame")) return;
    %init(SGNativeCompactTransition);
}
