#import "Core/SGCore.h"
#import "Native/Player/NowPlaying.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

static NSString *const kPressScaleKey = @"sg.barPressScale";
static NSString *const kPressLightName = @"sg.barPressLight";

static void scaleForPress(CALayer *layer, BOOL pressed) {
    if (!layer) return;
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [layer removeAnimationForKey:kPressScaleKey];
        return;
    }
    NSString *scale = @"transform.scale";
    NSNumber *rest = [layer valueForKeyPath:scale];
    NSNumber *current = [(layer.presentationLayer ?: layer) valueForKeyPath:scale];
    if (pressed) {
        CABasicAnimation *down = [CABasicAnimation animationWithKeyPath:scale];
        down.fromValue = current;
        down.toValue = @(rest.doubleValue * 0.97);
        down.duration = 0.10;
        down.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        down.removedOnCompletion = NO;
        down.fillMode = kCAFillModeForwards;
        [layer addAnimation:down forKey:kPressScaleKey];
    } else {
        CASpringAnimation *up = [CASpringAnimation animationWithKeyPath:scale];
        up.fromValue = current;
        up.toValue = rest;
        up.stiffness = 420;
        up.damping = 30;
        up.duration = up.settlingDuration;
        [layer addAnimation:up forKey:kPressScaleKey];
    }
}

@interface SGBarPress : UIGestureRecognizer
- (void)layoutLight;
@end

@implementation SGBarPress {
    UITouch *_touch;
    CGPoint _start;
    CALayer *_light;
}

- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:NULL])) return nil;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesBegan = NO;
    self.delaysTouchesEnded = NO;
    return self;
}

- (BOOL)canPrevent:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePrevented:(UIGestureRecognizer *)other { return NO; }

- (void)layoutLight {
    CALayer *card = self.view.layer;
    _light.frame = card.bounds;
    _light.cornerRadius = card.cornerRadius;
    _light.cornerCurve = card.cornerCurve;
}

- (void)showPress:(BOOL)pressed {
    CALayer *card = self.view.layer;
    if (!card) return;
    if (!_light) {
        _light = [CALayer layer];
        _light.name = kPressLightName;
        _light.backgroundColor = UIColor.whiteColor.CGColor;
        _light.opacity = 0;
        _light.actions = @{@"opacity": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null,
                           @"cornerRadius": NSNull.null};
        [card addSublayer:_light];
    }
    [self layoutLight];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @((_light.presentationLayer ?: _light).opacity);
    _light.opacity = pressed ? 0.09 : 0;
    fade.toValue = @(_light.opacity);
    fade.duration = pressed ? 0.10 : 0.18;
    [_light addAnimation:fade forKey:@"opacity"];
    scaleForPress(card, pressed);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch || !SGFlag(SGKeyPlayerAMPolish, NO)) return;
    UITouch *touch = touches.anyObject;
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return;
    }
    _touch = touch;
    _start = [touch locationInView:self.view];
    [self showPress:YES];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_touch || ![touches containsObject:_touch]) return;
    CGPoint at = [_touch locationInView:self.view];
    if (hypot(at.x - _start.x, at.y - _start.y) > 10 || !CGRectContainsPoint(self.view.bounds, at)) [self reset];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self reset];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self reset];
}

- (void)reset {
    if (!_touch) return;
    _touch = nil;
    [self showPress:NO];
}

@end

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    static char cardKey, pressKey;
    UIView *card = SGFindIdentifier(((UIViewController *)self).view, @"SPTNowPlayingBar", &cardKey);
    if (!card) return;
    SGBarPress *press = objc_getAssociatedObject(card, &pressKey);
    if (!press) {
        press = [SGBarPress new];
        [card addGestureRecognizer:press];
        objc_setAssociatedObject(card, &pressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [press layoutLight];
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
}
