// Hold-to-speed-up preferences and its Mod Settings section, shared by both looks.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "HoldSpeed.h"

static const double kSpeeds[] = {1.5, 2.0, 3.0};
static const NSInteger kDefaultChoice = 1;

BOOL SGPlayerHoldSpeedEnabled(void) {
    return SGEnabled(SGKeyHoldSpeedEnabled);
}

NSArray<NSString *> *SGPlayerHoldSpeedNames(void) {
    return @[@"1.5×", @"2×", @"3×"];
}

NSInteger SGPlayerHoldSpeedChoice(void) {
    NSInteger choice = SGInt(SGKeyHoldSpeed, kDefaultChoice);
    NSInteger count = (NSInteger)(sizeof(kSpeeds) / sizeof(kSpeeds[0]));
    return choice >= 0 && choice < count ? choice : kDefaultChoice;
}

double SGPlayerHoldSpeed(void) {
    return kSpeeds[SGPlayerHoldSpeedChoice()];
}

NSString *SGPlayerHoldSpeedLabel(void) {
    return SGPlayerHoldSpeedNames()[(NSUInteger)SGPlayerHoldSpeedChoice()];
}

NSString *SGPlayerHoldSpeedAnnouncement(void) {
    return [NSString stringWithFormat:@"Playing at %g times speed", SGPlayerHoldSpeed()];
}

SGModSection *SGHoldSpeedSection(void) {
    SGModRow *toggle = SGSwitchRow(@"Hold cover to speed up", @"Hold either side of the cover to play faster", SGKeyHoldSpeedEnabled);
    SGModRow *speed = SGSegmentRow(@"Speed", nil, SGPlayerHoldSpeedNames(), ^NSInteger {
        return SGPlayerHoldSpeedChoice();
    }, ^(NSInteger index) {
        SGSetInt(SGKeyHoldSpeed, index);
    });
    speed.waitsOn = SGKeyHoldSpeedEnabled;
    return SGNotedSection(@"Hold to speed up", @[toggle, speed],
        @"Hold the left or right side of the cover to play faster until you lift your finger. Applies at once.");
}
