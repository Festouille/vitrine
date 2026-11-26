#import "Shared/Haptics/SGHapticRelay.h"

NSNotificationName const SGHapticRelayAvailableNotification = @"SGHapticRelayAvailableNotification";
BOOL SGHapticRelayAvailable(void) { return NO; }
BOOL SGHapticEverywhereOffered(void) { return NO; }
BOOL SGHapticAddonOutdated(void) { return NO; }
BOOL SGHapticRelayQuiet(void) { return NO; }
void SGHapticAddonExplain(NSString *feature) {}
void SGHapticAddonShareSoon(void) {}
void SGHapticRelayAsk(void) {}
void SGHapticRelaySendLockScreen(void) {}
void SGHapticRelayTap(float intensity, float sharpness) {}
void SGHapticRelayRumble(float level) {}
