#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Settings/SGPage.h"
#import "Settings/SGModPage.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Native/LocalFiles/LocalLyrics.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"

void SGHarnessStartClock(double at, double rate, double pauseAt, double holdFor);

void SGDressPageBar(UIViewController *page) {}
void SGPlacePageBar(UIViewController *page) {}
void SGUndressPageBar(UIViewController *page) {}
void SGOpenModSettings(UIView *source) {}
__weak UIView *sgr_sheetChromeRoot = nil;
void SGRWatchSheetPaint(UIView *root) {}
BOOL SGSingButtonShown(void) { return NO; }
void SGKaraokeRefreshImportedTranslation(NSString *trackID) {}
BOOL SGKaraokeInAnotherLanguage(NSArray<SGKaraokeLine *> *lines, NSString *language) { return NO; }
NSString *SGLyricsErrorTitle(NSString *error) { return @"Translation unavailable"; }

@interface SGImportHarnessTrack : NSObject
- (NSURL *)URI;
- (NSString *)trackTitle;
- (NSString *)artistName;
@end
@implementation SGImportHarnessTrack
- (NSURL *)URI { return [NSURL URLWithString:@"spotify:track:0123456789012345678901"]; }
- (NSString *)trackTitle { return @"Harness Song"; }
- (NSString *)artistName { return @"Vitrine"; }
@end

@interface SGImportHarnessState : NSObject
- (SGImportHarnessTrack *)track;
- (BOOL)isPaused;
- (double)positionAsOfTimestamp;
- (double)playbackSpeed;
@end
@implementation SGImportHarnessState
- (SGImportHarnessTrack *)track { return [SGImportHarnessTrack new]; }
- (BOOL)isPaused { return YES; }
- (double)positionAsOfTimestamp { return 15; }
- (double)playbackSpeed { return 1; }
@end

SPTPlayerState *SGPlayerState(void) { return (id)[SGImportHarnessState new]; }
NSString *SGURIString(id uri) { return [uri absoluteString]; }

@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
NSArray<NSString *> *SGLyricsOrder(void) { return @[]; }
void SGLyricsSetOrder(NSArray<NSString *> *keys) {}
SGLyricsProvider *SGLyricsProviderFor(NSString *key) { return nil; }
BOOL SGEeveeLyricsOn(void) { return NO; }
SGModRow *SGSpicyLyricsKeyRow(void) { return SGPageRow(@"Spicy Lyrics", ^UIViewController *{ return nil; }); }
UIViewController *SGLyricsSourcesPage(void) { return nil; }
NSArray<NSString *> *SGLyricsTranslationLanguageNames(void) { return @[]; }
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray *at = [NSMutableArray array], *words = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        [at addObject:@(line.start)];
        [words addObject:SGKaraokeLineText(line)];
    }
    *starts = at;
    *texts = words;
}

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
    if (!ok) exit(1);
}

UIViewController *SGHarnessImportPage(NSString *scenario) {
    BOOL native = [scenario hasPrefix:@"native"];
    SGModSection *sources = SGLyricsSourcesSection(!native);
    SGModRow *toggle = nil, *autoSelect = nil;
    for (SGModRow *row in sources.rows) {
        if ([row.key isEqualToString:SGKeyTrackLyricsImport]) toggle = row;
        if ([row.key isEqualToString:SGKeyLyricsAutoSelect]) autoSelect = row;
    }
    check(toggle && !toggle.defaultOn, @"Mod Settings exposes the import switch, off by default");
    check(autoSelect && !autoSelect.defaultOn, @"Mod Settings exposes Automatic best source, off by default");
    for (NSString *name in SGImportedTrackLyricsFiles()) SGDeleteImportedLRC(name);
    SGSetEnabled(SGKeyTrackLyricsImport, YES);

    NSString *uri = SGURIString(SGPlayerState().track.URI);
    NSURL *ttml = [NSBundle.mainBundle URLForResource:@"duet" withExtension:@"ttml"];
    NSURL *lrc = [NSBundle.mainBundle URLForResource:@"plain" withExtension:@"lrc"];
    NSError *error = nil;
    NSString *lrcName = SGImportTrackLyrics(lrc, uri, &error);
    check(lrcName != nil, error.localizedDescription ?: @"LRC imported from Files");
    SGLyricsResult *line = SGTrackLyricsOverride(@"0123456789012345678901");
    check(line.synced && !line.wordTimed && line.texts.count, @"LRC is line synced and linked by Spotify ID");
    check(!SGTrackLyricsOverride(@"1123456789012345678901"), @"Import does not affect another track");
    NSString *ttmlName = SGImportTrackLyrics(ttml, uri, &error);
    check(ttmlName != nil, error.localizedDescription ?: @"TTML imported from Files");
    SGLyricsResult *words = SGTrackLyricsOverride(uri);
    check(words.wordTimed && words.karaokeLines.count && [words.provider isEqualToString:@"Imported TTML"], @"TTML replaces LRC and keeps word timings");
    BOOL backing = NO, duet = NO;
    for (SGKaraokeLine *verse in words.karaokeLines) {
        backing |= verse.backing != nil;
        duet |= verse.align == SGKaraokeAlignTrailing;
    }
    check(backing && duet, @"TTML retains backing and duet vocals");
    SGSetEnabled(SGKeyTrackLyricsImport, NO);
    check(!SGTrackLyricsOverride(uri), @"Switch off restores source fallback without deleting files");
    SGSetEnabled(SGKeyTrackLyricsImport, YES);
    check(SGTrackLyricsOverride(uri) == words, @"Switch on restores the assignment");
    SGDeleteImportedLRC(lrcName);
    if ([scenario hasSuffix:@"settings"]) {
        if (!native) return SGRLyricsSettingsPage(@"Lyrics", nil, @[sources]);
        return [[SGModPage alloc] initWithTitle:@"Lyrics" intro:nil sections:@[sources] footer:nil];
    }
    if ([scenario hasSuffix:@"files"]) return SGImportedLRCPage();
    if (native) return SGLocalLyricsPage();
    SGKaraokeKeepLines(@"harness", words.karaokeLines);
    SGHarnessStartClock(15000, 0, -1, 0);
    UIViewController *page = [UIViewController new];
    page.title = @"Imported TTML";
    page.view.backgroundColor = UIColor.blackColor;
    SGRKaraokeView *view = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [page.view addSubview:view];
    UILayoutGuide *safe = page.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:safe.topAnchor], [view.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor], [view.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
    ]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        check([view valueForKey:@"tops"] != nil, @"Redesigned renderer lays out imported lyrics");
    });
    return page;
}
