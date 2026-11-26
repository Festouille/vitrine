// Stand-ins for features that need Spotify at runtime.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPage.h"
#import "Shared/AdBlock/AdBlock.h"
#import "Shared/Haptics/SGHapticRelay.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Privacy/Privacy.h"
#import "Shared/SponsorBlock/SGSponsorBlock.h"

extern BOOL SGHarnessWarning;
extern BOOL SGHarnessOnboarding;

static UIViewController *blank(NSString *title) {
    return [[SGModPage alloc] initWithTitle:title intro:nil sections:@[] footer:nil];
}

#define PAGE(name) UIViewController *name(void) { return blank(@#name); }
PAGE(SGAboutPage) PAGE(SGAllFlagsPage) PAGE(SGArtistBlockSettingsPage) PAGE(SGDSPSettingsPage) PAGE(SGAutoMixSettingsPage)
PAGE(SGGesturesSettingsPage) PAGE(SGHeadGesturesSettingsPage) PAGE(SGLabsPage)
PAGE(SGListeningStatsPage) PAGE(SGLiveActivitySettingsPage) PAGE(SGLockScreenWidgetPage) PAGE(SGNavbarSettingsPage)
PAGE(SGNowPlayingBarSettingsPage) PAGE(SGRAlbumSettingsPage) PAGE(SGRArtistSettingsPage)
PAGE(SGRNavbarSettingsPage) PAGE(SGRHomeSettingsPage)
PAGE(SGSingSettingsPage) PAGE(SGSpatialVoiceSettingsPage) PAGE(SGVibrationsSettingsPage)
UIViewController *SGRPlayerSettingsPage(NSArray *more) {
    return [[SGModPage alloc] initWithTitle:@"Player" intro:nil sections:more footer:nil];
}
UIViewController *SGRLyricsSettingsPage(NSString *title, NSString *intro, NSArray<SGModSection *> *sections) {
    return [[SGModPage alloc] initWithTitle:title intro:intro sections:sections footer:nil];
}
UIViewController *SGHomeSettingsPage(void) {
    NSString *gate = @"spotifyglass.harness.searchGate";
    SGModRow *library = SGPageRow(@"Library options", ^UIViewController *{
        return [[SGModPage alloc] initWithTitle:@"Library options" intro:nil sections:@[
            SGSection(nil, @[SGOptionRow(@"Library detail switch", nil, @"spotifyglass.harness.libraryDetail")]),
        ] footer:nil];
    });
    library.waitsOn = gate;
    SGModRow *literal = SGActionRow(@"Calm", nil, ^{});
    literal.literal = YES;
    return [[SGModPage alloc] initWithTitle:@"Home & Library" intro:nil sections:@[
        SGSection(nil, @[SGPageRow(@"Gradient", ^UIViewController *{
            return [[SGModPage alloc] initWithTitle:@"Gradient" intro:nil sections:@[
                SGSection(nil, @[SGOptionRow(@"Show gradient", @"Color at the top of Home", @"spotifyglass.harness.gradient")]),
            ] footer:nil];
        })]),
        SGSection(nil, @[SGOptionRow(@"Enable Library options", nil, gate), library]),
        SGSection(nil, @[literal]),
    ] footer:nil];
}

#define ROW(name) SGModRow *name(void) { return SGPageRow(@#name, ^UIViewController *{ return nil; }); }
NSArray<SGModRow *> *SGAITranslatorRows(void) { return @[SGPageRow(@"SGAITranslatorRows", ^UIViewController *{ return nil; })]; }
ROW(SGAppIconRow) ROW(SGLyricsMeaningsRow)
ROW(SGSavedTranslationsRow) ROW(SGTranslateEverySongRow)
ROW(SGRLyricsHideRow)
NSArray<SGModRow *> *SGOnDeviceTranslatorRows(void) { return @[SGPageRow(@"SGOnDeviceTranslatorRows", ^UIViewController *{ return nil; })]; }
NSArray<SGModRow *> *SGAppFontRows(void) { return @[]; }
NSArray<SGModRow *> *SGNativeAppearanceRows(void) { return @[]; }
NSArray<SGModRow *> *SGRAppearanceRows(void) { return @[]; }
SGModSection *SGDefaultPlaylistSection(void) { return nil; }
NSArray<NSDictionary *> *SGBlockedArtists(void) { return @[]; }

PAGE(SGLyricsSourcesPage) PAGE(SGImportedLRCPage) PAGE(SGSponsorBlockSettingsPage)
SGModRow *SGSpicyLyricsKeyRow(void) { return SGActionRow(@"Spicy Lyrics Key", nil, ^{}); }
NSArray<NSString *> *SGLyricsOrder(void) { return @[]; }
SGLyricsProvider *SGLyricsProviderFor(NSString *key) { return nil; }
NSArray<NSString *> *SGLyricsTranslationLanguageNames(void) { return @[@"Any"]; }
NSArray<NSString *> *SGImportedLRCFiles(void) { return @[]; }
NSArray<NSString *> *SGImportedTrackLyricsFiles(void) { return @[]; }
NSString *SGKaraokePlayingTrack(void) { return nil; }
void SGKaraokeRefreshImportedTranslation(NSString *trackID) {}
NSNotificationName const SGTrackLyricsDidChangeNotification = @"SGTrackLyricsDidChangeNotification";
BOOL SGEeveeLyricsOn(void) { return NO; }
NSInteger SGKaraokeDelayMs(void) { return 0; }
NSString *const SGLyricsRomanisedDidChangeNotification = @"SGLyricsRomanisedDidChangeNotification";

NSArray<NSString *> *SGAdBlockLabels(void) { return @[]; }
NSUInteger SGAdBlockCount(NSString *label) { return 0; }
NSUInteger SGAdBlockChecked(NSString *label) { return NSNotFound; }
void SGResetAdBlock(void) {}
NSArray<NSString *> *SGBlockedLabels(void) { return @[]; }
NSUInteger SGBlockedCount(NSString *label) { return 0; }
void SGResetBlocked(void) {}
NSString *SGSponsorBlockSummary(void) { return nil; }
void SGSponsorBlockPreferencesDidChange(void) {}

NSString *SGDSPSummary(void) { return @"Off"; }
NSString *SGAutoMixSummary(void) { return @"Off"; }
NSString *SGSingSummary(void) { return @"Off"; }
// An iPhone that reads headphone motion, with Spatial voice off.
BOOL SGSingSpatialAvailable(void) { return YES; }
BOOL SGSingSpatial(void) { return NO; }

void SGDressPageBar(UIViewController *page) {}
void SGPlacePageBar(UIViewController *page) {}
void SGUndressPageBar(UIViewController *page) {}
BOOL SGHapticAddonOutdated(void) { return NO; }
BOOL SGHapticEverywhereOffered(void) { return NO; }
BOOL SGHapticRelayAvailable(void) { return NO; }
void SGHapticAddonExplain(NSString *feature) {}
void SGHapticAddonShareSoon(void) {}
void SGHapticRelaySendLockArt(void) {}

void SGCheckForUpdate(BOOL force) {}
void SGWatchForUpdates(void) {}
// Signing.m is the real one: its row stays away while the harness's own signature is sound, and its
// "Signed until" row shows once the .app holds an embedded.mobileprovision (README).
BOOL SGOnboardingShowing(void) { return SGHarnessOnboarding; }
// Environment.m's red row, as a phone with EeveeSpotify injected too shows it.
NSArray<SGModRow *> *SGEnvironmentWarningRows(void) {
    if (!SGHarnessWarning) return @[];
    return @[SGWarningRow(@"EeveeSpotify is injected too", @"Tap to see what that changes", ^{})];
}
// The lock screen's source order row (MotionSources.m), for AnimatedArtworkSettings.m.
SGModRow *SGMotionSourcesRow(void) { return SGStatRow(@"Sources", ^NSString *{ return @"Canvas, Apple Music"; }); }
