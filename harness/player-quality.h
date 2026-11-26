#import "Core/SGPrefs.h"

@interface SPTPlaybackQuality : NSObject
@property (nonatomic) unsigned long long bitrateLevel;
@end
@implementation SPTPlaybackQuality
@end

static void SGHarnessQualityChecks(NSString *look, UIView *header, NSString *key, BOOL shown,
                                   void (^report)(SPTPlaybackQuality *quality)) {
    UILabel *(^badge)(void) = ^{
        for (UIView *view in header.subviews) {
            if ([view.accessibilityIdentifier isEqualToString:@"sg.audio-quality"]) return (UILabel *)view;
        }
        return (UILabel *)nil;
    };
    BOOL (^visible)(void) = ^BOOL { return badge() && !badge().hidden; };
    void (^send)(unsigned long long) = ^(unsigned long long value) {
        SPTPlaybackQuality *quality = [SPTPlaybackQuality new];
        quality.bitrateLevel = value;
        report(quality);
    };
    SGSetEnabled(key, NO);
    send(5);
    BOOL ok = !visible();
    SGSetEnabled(key, YES);
    NSArray<NSString *> *labels = @[@"Low", @"Normal", @"High", @"Very high", @"Lossless", @"Lossless"];
    for (NSUInteger i = 0; i < labels.count; i++) {
        send(i + 1);
        ok &= visible() && [badge().text isEqualToString:labels[i]];
    }
    UILabel *label = badge();
    ok &= label && !label.userInteractionEnabled && CGRectGetMinY(label.frame) >= CGRectGetMaxY(header.bounds);
    for (NSNumber *unknown in @[@0, @7, @1000]) {
        send(unknown.unsignedLongLongValue);
        ok &= !visible();
    }
    report(nil);
    ok &= !visible();
    send(shown ? 6 : 0);
    ok &= visible() == shown;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        NSLog(@"QUALITY READY: %@ %@ -- %@", look, shown ? @"shown" : @"hidden", ok ? @"PASS" : @"FAIL");
    });
}
