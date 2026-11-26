// CarPlay lyrics and playback controls, under either look (Native or Redesigned).
// Off until switched on in Mod Settings > CarPlay (SGKeyCarPlay): when off, no CarPlay hooks install.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CPNowPlayingButton, SGKaraokeLine;

// Master switch, off by default. Read at launch by CarPlay.x.
#define SGKeyCarPlay @"spotifyglass.carPlay"
// Show a Lyrics button on CarPlay's Now Playing screen that opens live synced lyrics.
#define SGKeyCarPlayLyrics @"spotifyglass.carPlay.lyrics"
// Show the current lyric line in CarPlay's Now Playing artist slot while connected (yields to Lock Screen Lyrics).
#define SGKeyCarPlayNowPlayingLine @"spotifyglass.carPlay.nowPlayingLine"
// Show line translations under each line in CarPlay Lyrics when available.
#define SGKeyCarPlayTranslations @"spotifyglass.carPlay.translations"
// Show a Controls button on CarPlay's Now Playing screen (speed, +/-15s seek, sleep timer, karaoke, audio effects).
#define SGKeyCarPlayControls @"spotifyglass.carPlay.controls"
// Guard CarPlay Assistant Cell callbacks against NSException crashes on resigned/sideloaded builds.
#define SGKeyCarPlayCrashFix @"spotifyglass.carPlay.crashFix"

// Apple's hard limit for -[CPNowPlayingTemplate updateNowPlayingButtons:].
static const NSUInteger SGCarPlayMaxButtons = 5;

// Mod Settings > CarPlay page and its summary label on Mod Settings' main page.
UIViewController *SGCarPlaySettingsPage(void);
NSString *SGCarPlaySummary(void);

// One displayable row for the CarPlay Lyrics list template.
@interface SGCarPlayLyricEntry : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic) NSInteger startMs;
@property (nonatomic) NSInteger lineIndex;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL seekable;
@end

// Builds the driving-safe window of lyric rows for CarPlay, keeping the active line near the top
// so it stays visible even under CarPlay Limited UI item caps.
NSArray<SGCarPlayLyricEntry *> *SGCarPlayLyricsEntries(
    NSArray<SGKaraokeLine *> *lines,
    NSInteger positionMs,
    NSInteger delayMs,
    BOOL showTranslations,
    BOOL romanised,
    BOOL romanisedReplace,
    NSUInteger maxItems,
    NSInteger * _Nullable outActiveIndex);

// Returns the single current lyric line for CarPlay's Now Playing artist slot, or nil during breaks / plain lyrics.
NSString * _Nullable SGCarPlayNowPlayingLyricLine(
    NSArray<SGKaraokeLine *> *lines,
    NSInteger positionMs,
    NSInteger delayMs,
    BOOL showTranslation,
    BOOL romanised,
    BOOL romanisedReplace,
    NSInteger * _Nullable outMsToChange);

// Merges Spotify's Now Playing buttons with Vitrine's buttons without ever exceeding SGCarPlayMaxButtons (5).
// Any displaced CPNowPlayingMoreButton is returned in outDisplacedMore so Controls can still expose it.
NSArray<CPNowPlayingButton *> *SGCarPlayMergedButtons(
    NSArray<CPNowPlayingButton *> *spotifyButtons,
    NSArray<CPNowPlayingButton *> *vitrineButtons,
    CPNowPlayingButton * _Nullable * _Nullable outDisplacedMore);

// Playback speed presets and display formatting for CarPlay Controls.
NSArray<NSNumber *> *SGCarPlaySpeedPresets(void);
NSString *SGCarPlayFormatSpeed(double speed);
NSString *SGCarPlayFormatSleepTimer(NSInteger mode, NSDate * _Nullable endDate, NSDate *now);

NS_ASSUME_NONNULL_END
