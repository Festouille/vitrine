#import "Core/SGCore.h"
#import "Shared/Player/QueueHelpers.h"
#import "Redesigned/NowPlaying/QueueDuration.h"

@interface SGRQueueDurationLabel : UILabel <SGPlayerStateObserver>
@end

@implementation SGRQueueDurationLabel
- (void)playerStateDidChange:(SPTPlayerState *)state {}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (!self.window) return;
    NSString *duration = SGQueueDurationText(state);
    if (![self.text isEqualToString:duration]) self.text = duration;
}
@end

static char kDurationLabel;

%hook _TtC14Queue_ViewImpl19QueueViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *controller = (UIViewController *)self;
    SGRQueueDurationLabel *label = objc_getAssociatedObject(controller, &kDurationLabel);
    if (!label) {
        label = [SGRQueueDurationLabel new];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.accessibilityIdentifier = @"spotifyglass.queue.durationLabel";
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        label.adjustsFontForContentSizeCategory = YES;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor colorWithWhite:1 alpha:0.70];
        label.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        label.text = SGQueueDurationText(SGPlayerState());
        [controller.view addSubview:label];
        UILayoutGuide *safe = controller.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:safe.bottomAnchor],
            [label.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
            [label.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
            [label.heightAnchor constraintEqualToConstant:28],
        ]];
        objc_setAssociatedObject(controller, &kDurationLabel, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGAddPlayerStateObserver(label);
        UIEdgeInsets insets = controller.additionalSafeAreaInsets;
        insets.bottom += 28;
        controller.additionalSafeAreaInsets = insets;
    }
    [label playerStateDidReport:SGPlayerState()];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGFlag(SGRKeyQueueDuration, NO)) return;
    %init;
}
