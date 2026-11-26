#import "Core/SGCore.h"
#import "NowPlaying.h"

@interface SPTBarOverlayPresentationTransition : NSObject
- (id<UIViewControllerContextTransitioning>)transitioningContext;
- (UIView *)overlayView;
- (UIView *)barSnapshotView;
- (double)progress;
@end

%hook SPTBarOverlayPresentationTransition
- (void)setProgress:(double)progress {
    %orig;
    if (!SGFlag(SGKeyPlayerAMPolish, NO) || UIAccessibilityIsReduceMotionEnabled()) return;
    UIView *container = [self transitioningContext].containerView;
    UIView *player = [self overlayView], *bar = [self barSnapshotView];
    if (!container || !player || !bar || player.superview != container || bar.superview != container ||
        container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return;

    CGFloat t = MIN(1, MAX(0, [self progress] / 0.85));
    CGFloat blend = t * t * (3 - 2 * t);
    [UIView performWithoutAnimation:^{
        player.alpha = blend;
        bar.alpha = 1 - blend;
    }];
}
%end

%ctor {
    if (!SGNativeUI()) return;
    Class animator = NSClassFromString(@"SPTBarOverlayPresentationTransition");
    if (!class_getInstanceMethod(animator, @selector(setProgress:)) ||
        !class_getInstanceMethod(animator, @selector(progress)) ||
        !class_getInstanceMethod(animator, @selector(transitioningContext)) ||
        !class_getInstanceMethod(animator, @selector(overlayView)) ||
        !class_getInstanceMethod(animator, @selector(barSnapshotView))) return;
    %init;
}
