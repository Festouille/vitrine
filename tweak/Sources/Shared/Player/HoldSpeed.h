// Hold either side of the player's cover to play faster until the finger lifts, under either look
// (Native/Player/PlayerGestures.x, Redesigned/Player/PlayerArtwork.x). On at 2x until changed in Mod Settings.
#import <Foundation/Foundation.h>

@class SGModSection;

// On until switched off (SGEnabled), off after Reset all settings.
#define SGKeyHoldSpeedEnabled @"spotifyglass.player.holdSpeed"
// Index into SGPlayerHoldSpeedNames(): 0 = 1.5x, 1 = 2x (default), 2 = 3x.
#define SGKeyHoldSpeed @"spotifyglass.player.holdSpeedRate"

BOOL SGPlayerHoldSpeedEnabled(void);
NSArray<NSString *> *SGPlayerHoldSpeedNames(void);
NSInteger SGPlayerHoldSpeedChoice(void);
double SGPlayerHoldSpeed(void);
NSString *SGPlayerHoldSpeedLabel(void);
NSString *SGPlayerHoldSpeedAnnouncement(void);

// The Hold to speed up section for the Player page in Mod Settings.
SGModSection *SGHoldSpeedSection(void);
