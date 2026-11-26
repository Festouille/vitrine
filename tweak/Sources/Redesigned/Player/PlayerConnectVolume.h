#import <UIKit/UIKit.h>

extern NSString *const SGRConnectVolumeDidChangeNotification;
BOOL SGRPlayerConnectVolumeOn(void);
NSString *SGRConnectVolumeRoute(double *value);
BOOL SGRConnectSetVolume(NSString *route, double value, BOOL final);
void SGRConnectVolumeRowVisible(UIControl *row, BOOL visible);
