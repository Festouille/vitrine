#import "Settings/SGModPage.h"

void SGRememberLaunchSettings(void);
NSArray<NSString *> *SGPendingRestartSettings(void);
NSDictionary<NSString *, NSNumber *> *SGReadPresetJSON(NSString *json, NSUInteger *skipped);
SGModRow *SGSettingsPresetsRow(void);

@interface SGModSettingsPage : SGModPage
@end
