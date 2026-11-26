// Mod Settings > CarPlay: master default-off switch, lyrics options, playback controls, and sideload crash guard.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGLocalize.h"
#import "CarPlay.h"

NSString *SGCarPlaySummary(void) {
    return SGFlag(SGKeyCarPlay, NO) ? SGL(@"On") : SGL(@"Off");
}

UIViewController *SGCarPlaySettingsPage(void) {
    SGModRow *master = SGOptionRow(@"Enable CarPlay enhancements",
        @"Adds synced lyrics and quick playback controls to Spotify in CarPlay",
        SGKeyCarPlay);

    SGModRow *lyrics = SGSwitchRow(@"Lyrics screen",
        @"Adds a Lyrics button on CarPlay Now Playing with tap-to-seek synced lines",
        SGKeyCarPlayLyrics);
    lyrics.waitsOn = SGKeyCarPlay;

    SGModRow *nowPlayingLine = SGSwitchRow(@"Now Playing lyric line",
        @"Shows the current line in CarPlay Now Playing when Lock screen lyrics is off",
        SGKeyCarPlayNowPlayingLine);
    nowPlayingLine.waitsOn = SGKeyCarPlay;

    SGModRow *translations = SGSwitchRow(@"Show translations",
        @"Shows translated lyrics under each line in CarPlay when available",
        SGKeyCarPlayTranslations);
    translations.waitsOn = SGKeyCarPlay;

    SGModRow *controls = SGSwitchRow(@"Playback controls",
        @"Adds a Controls button for speed, ±15 s seek, sleep timer, karaoke and audio effects",
        SGKeyCarPlayControls);
    controls.waitsOn = SGKeyCarPlay;

    SGModRow *crashFix = SGSwitchRow(@"Sideload crash guard",
        @"Prevents CarPlay Assistant Cell exceptions on resigned Spotify builds",
        SGKeyCarPlayCrashFix);
    crashFix.waitsOn = SGKeyCarPlay;

    return [[SGModPage alloc] initWithTitle:@"CarPlay"
        intro:SGRestartNote
        sections:@[
            SGSection(nil, @[master]),
            SGSection(@"Lyrics", @[lyrics, nowPlayingLine, translations]),
            SGSection(@"Controls", @[controls]),
            SGNotedSection(@"Stability", @[crashFix],
                @"Resigned Spotify installs can raise an exception when CarPlay configures Siri's Assistant Cell. "
                @"Keeping this on catches that callback so CarPlay stays connected."),
        ]
        footer:@"Works in both Legacy and Redesigned UI. Buttons respect CarPlay's five-button Now Playing limit."];
}
