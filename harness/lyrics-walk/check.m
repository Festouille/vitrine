// Checks the walk down the sources' order and a source picked from the player's ⋯ (LyricsSources.m,
// LyricsPick.m) without the phone or the network: every source is answered here, by key, so a walk, a pick,
// a later walk with the pick's request failing or answering nothing, a pick landing while the walk runs, and
// Automatic after each can be driven on the Mac. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Settings/SGSourcesPage.h"
#import "Settings/SGPageStyle.h"
#import "Core/SGFlagForce.h"
#import "Core/SGPrefs.h"
#import "Headers/SPTPlayer.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

// What the walk and the pick reach outside themselves for. Every track is a named local file, so the sources
// that search by name are asked at once.
NSString *const SGSpicyLyricsKey = @"spicylyrics";
NSString *const SGImportedLRCKey = @"importedLRC";
static NSString *sg_linkedTrack;
NSString *SGTrackLyricsLinkedTo(NSString *track) { return [track isEqualToString:sg_linkedTrack] ? @"linked.ttml" : nil; }
SGLyricsResult *SGTrackLyricsOverride(NSString *track) { return nil; }
NSString *SGSpicyLyricsStatus(void) { return nil; }
BOOL SGLocalFileIs(NSString *uri) { return NO; }
NSDictionary<NSString *, id> *SGLocalFileInfo(NSString *uri) { return @{@"title": @"a", @"artist": @"b", @"seconds": @200}; }
SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) { return nil; }
BOOL SGLyricsStandAsideForEevee(void) { return NO; }
void SGRegisterFlagForcer(BOOL beatsOverride, SGFlagForcer atLaunch, SGFlagForcer locked) {}
UIViewController *SGTopController(void) { return nil; }
UIViewController *SGSourcesPageMake(NSString *title, NSString *note, NSArray<SGSource *> *all,
                                    NSArray<NSString *> *(^order)(void), void (^setOrder)(NSArray<NSString *> *keys)) { return nil; }
@implementation SGSource
+ (instancetype)sourceWithKey:(NSString *)key name:(NSString *)name detail:(NSString *)detail { return nil; }
@end

// The lyrics view: the lines kept for each track, NSNull once kept as none, and the tracks asked for again.
static NSMutableDictionary<NSString *, id> *sg_shown;
static NSMutableArray<NSString *> *sg_askedAgain;
void SGKaraokeKeepLines(NSString *track, NSArray<SGKaraokeLine *> *lines) { sg_shown[track] = lines ?: NSNull.null; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *track) {
    id lines = sg_shown[track];
    return lines == NSNull.null ? nil : lines;
}
void SGKaraokeAskAgain(NSString *track) {
    [sg_askedAgain addObject:track];
    [sg_shown removeObjectForKey:track];
}

// The sources, answered by key: a fresh result each ask, nil for none. One key may be held until release()
// runs, for what lands while the walk waits on it. Every ask is listed as "key:track".
typedef SGLyricsResult *(^SGAnswer)(void);
static NSMutableDictionary<NSString *, SGAnswer> *sg_answers;
static NSMutableArray<NSString *> *sg_asked;
static NSString *sg_held;
static void (^sg_release)(void);

static void answer(NSString *key, SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    [sg_asked addObject:[NSString stringWithFormat:@"%@:%@", key, query.trackID]];
    void (^now)(void) = ^{
        SGAnswer answer = sg_answers[key];
        done(answer ? answer() : nil);
    };
    if ([key isEqualToString:sg_held]) sg_release = now;
    else now();
}
#define ASK(name, key) SGLyricsAsk name = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) { answer(key, query, done); };
ASK(SGBiniLyricsAsk, @"binilyrics")
ASK(SGMusixmatchAsk, @"musixmatch")
ASK(SGUnisonAsk, @"unison")
ASK(SGNetEaseAsk, @"netease")
ASK(SGLrcLibAsk, @"lrclib")
ASK(SGSpicyLyricsAsk, @"spicylyrics")
ASK(SGQQMusicAsk, @"qqmusic")
ASK(SGKuGouAsk, @"kugou")
ASK(SGImportedLRCAsk, @"importedLRC")
ASK(SGGeniusAsk, @"genius")

// Two lines, timed by the line or not at all, with the page's text made from them as a source would.
static SGAnswer lines(BOOL timed) {
    return ^SGLyricsResult *{
        SGLyricsResult *result = [SGLyricsResult new];
        result.karaokeLines = timed ? SGKaraokeEstimatedLines(@[@1000, @2000], @[@"a", @"b"]) : SGKaraokeStaticLines(@[@"a", @"b"]);
        result.synced = timed;
        NSArray<NSNumber *> *starts;
        NSArray<NSString *> *texts;
        SGLyricsPageLines(result.karaokeLines, &starts, &texts);
        result.starts = starts;
        result.texts = texts;
        return result;
    };
}

// Word-timed lines with optional translation and (line- or word-timed) pronunciation metadata.
static SGAnswer wordLines(BOOL translation, BOOL pronunciation, BOOL wordPronunciation) {
    return ^SGLyricsResult *{
        SGKaraokeWord *w1 = [SGKaraokeWord new];
        w1.text = @"hello"; w1.start = 1000; w1.end = 1500;
        SGKaraokeWord *w2 = [SGKaraokeWord new];
        w2.text = @"world"; w2.start = 1500; w2.end = 2000;
        SGKaraokeLine *line = [SGKaraokeLine new];
        line.words = @[w1, w2];
        line.start = 1000; line.end = 2000;
        line.timing = SGKaraokeTimingWords;
        if (translation) line.translation = @"bonjour le monde";
        if (pronunciation) {
            SGKaraokeWord *pw = [SGKaraokeWord new];
            pw.text = @"helo"; pw.start = 1000; pw.end = 2000;
            SGKaraokeLine *pron = [SGKaraokeLine new];
            pron.words = @[pw];
            pron.start = 1000; pron.end = 2000;
            pron.timing = wordPronunciation ? SGKaraokeTimingWords : SGKaraokeTimingLine;
            line.pronunciation = pron;
        }
        SGLyricsResult *result = [SGLyricsResult new];
        result.karaokeLines = @[line];
        result.synced = YES;
        result.wordTimed = YES;
        NSArray<NSNumber *> *starts;
        NSArray<NSString *> *texts;
        SGLyricsPageLines(result.karaokeLines, &starts, &texts);
        result.starts = starts;
        result.texts = texts;
        return result;
    };
}

// A request lost on the way: counted as every source's are, so the walk knows nothing was not no lyrics.
static SGAnswer failing(void) {
    return ^SGLyricsResult *{
        SGLyricsNoteReply(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);
        return nil;
    };
}

static void pump(BOOL (^until)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!until() && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    CHECK(until());
}

static SGLyricsResult *fetch(NSString *track) {
    __block BOOL answered = NO;
    __block SGLyricsResult *got = nil;
    SGLyricsFetch(track, ^(SGLyricsResult *result) {
        got = result;
        answered = YES;
    });
    pump(^BOOL { return answered; });
    return got;
}

static NSDictionary<NSString *, SGLyricsResult *> *offers(NSString *track) {
    __block NSDictionary<NSString *, SGLyricsResult *> *got = nil;
    SGLyricsOffers(track, 0, ^(NSDictionary<NSString *, SGLyricsResult *> *offered) { got = offered; });
    pump(^BOOL { return got != nil; });
    return got;
}

// The walk keeps its answers for 40 tracks and then forgets them all: 40 other tracks walked forget the ones
// before. The same 40 picked forget what Automatic puts back for the ones before.
static NSUInteger sg_others;
static void walkOthers(BOOL picked) {
    sg_answers[@"musixmatch"] = lines(YES);
    for (NSUInteger i = 0; i < 40; i++) {
        NSString *track = [NSString stringWithFormat:@"other%lu", (unsigned long)++sg_others];
        if (!picked) {
            fetch(track);
            continue;
        }
        offers(track);
        SGLyricsChooseSource(track, @"musixmatch");
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        sg_shown = [NSMutableDictionary dictionary];
        sg_askedAgain = [NSMutableArray array];
        sg_answers = [NSMutableDictionary dictionary];
        sg_asked = [NSMutableArray array];
        // The order, read from the defaults, without writing the Mac's.
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"musixmatch", @"lrclib", @"netease", @"genius"]}
                                                       forName:NSArgumentDomain];
        sg_answers[@"musixmatch"] = lines(YES);
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = lines(YES);
        sg_answers[@"genius"] = lines(NO);

        // The walk stops at the first timed answer, the order's first, and its answer is nobody's pick.
        SGLyricsResult *got = fetch(@"t1");
        CHECK([got.provider isEqualToString:@"Musixmatch"] && got.synced && !got.picked);
        CHECK([sg_asked isEqualToArray:@[@"musixmatch:t1"]]);

        // A pick from the player's ⋯: the source's answer is the track's, marked as the pick's, and shows.
        NSDictionary *offered = offers(@"t1");
        CHECK(offered[@"musixmatch"] && offered[@"lrclib"] && offered[@"netease"]);
        SGLyricsChooseSource(@"t1", @"lrclib");
        got = fetch(@"t1");
        CHECK([got.provider isEqualToString:@"LRCLIB"] && got.picked && [SGLyricsChosenSource(@"t1") isEqualToString:@"lrclib"]);
        CHECK(sg_shown[@"t1"] == got.karaokeLines && [SGLyricsCreditFor(@"t1") isEqualToString:@"LRCLIB"]);

        // A later walk asks the pick first, and its lines are the walk's answer, as the pick's.
        walkOthers(NO);
        [sg_asked removeAllObjects];
        got = fetch(@"t1");
        CHECK([sg_asked isEqualToArray:@[@"lrclib:t1"]]);
        CHECK([got.provider isEqualToString:@"LRCLIB"] && got.picked);

        // The pick's request fails: the pick stands, the walk goes on, and its answer is kept as the order's
        // rather than as the pick's, so Spotify's own lines weigh against it. The next walk asks the pick again.
        walkOthers(NO);
        sg_answers[@"lrclib"] = failing();
        [sg_asked removeAllObjects];
        got = fetch(@"t1");
        CHECK([sg_asked isEqualToArray:(@[@"lrclib:t1", @"musixmatch:t1"])]);
        CHECK([got.provider isEqualToString:@"Musixmatch"] && !got.picked && [SGLyricsChosenSource(@"t1") isEqualToString:@"lrclib"]);
        CHECK(fetch(@"t1") == got);   // kept
        sg_answers[@"lrclib"] = lines(YES);
        walkOthers(NO);
        got = fetch(@"t1");
        CHECK([got.provider isEqualToString:@"LRCLIB"] && got.picked);

        // The pick has nothing: dropped, and the walk's answer is the order's.
        walkOthers(NO);
        sg_answers[@"lrclib"] = nil;
        got = fetch(@"t1");
        CHECK([got.provider isEqualToString:@"Musixmatch"] && !got.picked && !SGLyricsChosenSource(@"t1"));
        sg_answers[@"lrclib"] = lines(YES);

        // A pick made while the walk runs stands, with the walk begun on an earlier pick. That walk asked the
        // earlier pick first, so its answer is not what the order would choose: Automatic puts back what the
        // track showed before any pick, and the next request walks the order again.
        NSArray<SGKaraokeLine *> *spotify = SGKaraokeStaticLines(@[@"s"]);
        sg_shown[@"t2"] = spotify;
        offers(@"t2");
        SGLyricsChooseSource(@"t2", @"lrclib");
        CHECK(![sg_shown[@"t2"] isEqualToArray:spotify]);
        walkOthers(NO);
        sg_held = @"lrclib";
        __block SGLyricsResult *late = nil;
        SGLyricsFetch(@"t2", ^(SGLyricsResult *result) { late = result; });
        pump(^BOOL { return sg_release != nil; });
        SGLyricsChooseSource(@"t2", @"netease");
        sg_held = nil;
        sg_release();
        sg_release = nil;
        pump(^BOOL { return late != nil; });
        CHECK([late.provider isEqualToString:@"NetEase"] && late.picked && [SGLyricsChosenSource(@"t2") isEqualToString:@"netease"]);
        SGLyricsChooseAutomatic(@"t2");
        CHECK(!SGLyricsChosenSource(@"t2") && [sg_shown[@"t2"] isEqualToArray:spotify] && [SGLyricsCreditFor(@"t2") isEqualToString:@"Spotify"]);
        [sg_asked removeAllObjects];
        got = fetch(@"t2");
        CHECK([sg_asked isEqualToArray:@[@"musixmatch:t2"]] && [got.provider isEqualToString:@"Musixmatch"] && !got.picked);

        // Automatic once what it puts back is forgotten, 40 picks later: the track is asked for again as on a
        // first play, and the lines it shows are never dropped for none.
        offers(@"t3");
        SGLyricsChooseSource(@"t3", @"lrclib");
        walkOthers(YES);
        CHECK([SGLyricsChosenSource(@"t3") isEqualToString:@"lrclib"]);
        [sg_answers removeAllObjects];
        SGLyricsChooseAutomatic(@"t3");
        pump(^BOOL { return sg_askedAgain.count > 0; });
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        CHECK(!SGLyricsChosenSource(@"t3") && [sg_askedAgain isEqualToArray:@[@"t3"]] && !sg_shown[@"t3"]);
        CHECK(!fetch(@"t3"));

        // Prefer word-by-word timing (#111): a timed imported file first in the order ends the walk, though it is
        // timed by the line. Below a source timed as finely, it does not: the first in the order among equals stays.
        sg_answers[@"importedLRC"] = lines(YES);
        sg_answers[@"musixmatch"] = lines(YES);
        sg_answers[@"lrclib"] = lines(YES);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"importedLRC", @"musixmatch", @"lrclib"],
                                                                 SGKeyLyricsPreferWordTiming: @YES} forName:NSArgumentDomain];
        SGPrefsChanged();
        [sg_asked removeAllObjects];
        got = fetch(@"t4");
        CHECK([sg_asked isEqualToArray:@[@"importedLRC:t4"]] && [got.provider isEqualToString:@"Imported LRC"]);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"musixmatch", @"importedLRC", @"lrclib"],
                                                                 SGKeyLyricsPreferWordTiming: @YES} forName:NSArgumentDomain];
        SGPrefsChanged();
        [sg_asked removeAllObjects];
        got = fetch(@"t5");
        CHECK([sg_asked isEqualToArray:(@[@"musixmatch:t5", @"importedLRC:t5", @"lrclib:t5"])] && [got.provider isEqualToString:@"Musixmatch"]);

        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[]} forName:NSArgumentDomain];
        SGPrefsChanged();
        CHECK([SGLyricsForgetImportedAnswers() containsObject:@"t4"]);
        [sg_asked removeAllObjects];
        CHECK(!fetch(@"t4") && !sg_asked.count);

        // --- Automatic best lyrics source selection (SGKeyLyricsAutoSelect) ---
        NSMutableArray<NSString *> *chosenNotes = [NSMutableArray array];
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsSourceChosenNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:NSString.class]) [chosenNotes addObject:note.object];
        }];

        // 1. Default-off: line-timed first source stops immediately even when a word-timed source follows.
        SGLyricsSetAutoSelectWindow(0.2);
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"]}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [sg_asked removeAllObjects];
        got = fetch(@"auto_off");
        CHECK([got.provider isEqualToString:@"LRCLIB"] && !got.wordTimed);
        CHECK([sg_asked isEqualToArray:@[@"lrclib:auto_off"]]);

        // 2. Auto-select on: delivers first timed answer immediately without holding first render,
        //    then upgrades live when a word-timed source answers within the bounded window.
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [sg_asked removeAllObjects];
        [chosenNotes removeAllObjects];
        sg_held = @"netease";
        got = fetch(@"auto_upgrade");
        // First render returned immediately while netease is still in flight!
        CHECK([got.provider isEqualToString:@"LRCLIB"] && !got.wordTimed && !got.picked);
        CHECK(sg_release != nil);
        // Release netease within the window -> upgrades live!
        sg_held = nil;
        void (^releaseUpgrade)(void) = sg_release;
        sg_release = nil;
        releaseUpgrade();
        pump(^BOOL { return [chosenNotes containsObject:@"auto_upgrade"]; });
        SGLyricsResult *upgraded = fetch(@"auto_upgrade");
        CHECK([upgraded.provider isEqualToString:@"NetEase"] && upgraded.wordTimed && !upgraded.picked);
        CHECK(sg_shown[@"auto_upgrade"] == upgraded.karaokeLines && [SGLyricsCreditFor(@"auto_upgrade") isEqualToString:@"NetEase"]);

        // 3. Plain text never terminates search: skips past plain to line-timed, then upgrades to word-timed.
        [sg_answers removeAllObjects];
        sg_answers[@"genius"] = lines(NO);
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"genius", @"lrclib", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [chosenNotes removeAllObjects];
        got = fetch(@"auto_plain");
        CHECK([got.provider isEqualToString:@"LRCLIB"]);
        pump(^BOOL { return [chosenNotes containsObject:@"auto_plain"]; });
        CHECK([fetch(@"auto_plain").provider isEqualToString:@"NetEase"]);

        // 4. Same-tier facet tie-breaking: requested translation + word-timed pronunciation wins over plain word-timed;
        //    equal score keeps earlier source; optimal score closes window early.
        [sg_answers removeAllObjects];
        sg_answers[@"musixmatch"] = wordLines(NO, NO, NO);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);         // equal score -> should NOT replace musixmatch
        sg_answers[@"qqmusic"] = wordLines(YES, NO, NO);        // +1 translation -> upgrades
        sg_answers[@"binilyrics"] = wordLines(YES, YES, YES);   // +3 (translation + word-timed pronunciation) -> optimal!
        sg_answers[@"kugou"] = wordLines(YES, YES, YES);        // should NOT be asked once optimal reached
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"musixmatch", @"netease", @"qqmusic", @"binilyrics", @"kugou"],
                                                                 SGKeyLyricsAutoSelect: @YES,
                                                                 SGKeyLyricsTranslationLanguage: @7,
                                                                 SGKeyLyricsRomanised: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [sg_asked removeAllObjects];
        [chosenNotes removeAllObjects];
        got = fetch(@"auto_facets");
        CHECK([got.provider isEqualToString:@"Musixmatch"]);
        pump(^BOOL { return [fetch(@"auto_facets").provider isEqualToString:@"BiniLyrics"]; });
        CHECK(![sg_asked containsObject:@"kugou:auto_facets"]);

        // 5. Slow / stale response after bounded window expires is ignored.
        SGLyricsSetAutoSelectWindow(0.08);
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [chosenNotes removeAllObjects];
        sg_held = @"netease";
        got = fetch(@"auto_stale");
        CHECK([got.provider isEqualToString:@"LRCLIB"]);
        CHECK(sg_release != nil);
        // Wait past the 0.08s window before releasing netease.
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
        sg_held = nil;
        void (^releaseStale)(void) = sg_release;
        sg_release = nil;
        releaseStale();
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        CHECK([fetch(@"auto_stale").provider isEqualToString:@"LRCLIB"]);
        CHECK(![chosenNotes containsObject:@"auto_stale"]);

        // 6. Provider errors during upgrade window do not break the initial answer or block later sources.
        SGLyricsSetAutoSelectWindow(0.2);
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"musixmatch"] = failing();
        sg_answers[@"qqmusic"] = nil;
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"musixmatch", @"qqmusic", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [chosenNotes removeAllObjects];
        got = fetch(@"auto_err");
        CHECK([got.provider isEqualToString:@"LRCLIB"]);
        pump(^BOOL { return [chosenNotes containsObject:@"auto_err"]; });
        CHECK([fetch(@"auto_err").provider isEqualToString:@"NetEase"]);

        // 7. Manual pick during upgrade window is NEVER replaced by a late auto-select upgrade.
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"musixmatch"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"musixmatch", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        offers(@"auto_pick");
        [chosenNotes removeAllObjects];
        sg_held = @"netease";
        got = fetch(@"auto_pick");
        CHECK([got.provider isEqualToString:@"LRCLIB"]);
        CHECK(sg_release != nil);
        // User manually picks musixmatch while netease is still in flight.
        SGLyricsChooseSource(@"auto_pick", @"musixmatch");
        sg_held = nil;
        void (^releasePick)(void) = sg_release;
        sg_release = nil;
        releasePick();
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        CHECK([fetch(@"auto_pick").provider isEqualToString:@"Musixmatch"] && fetch(@"auto_pick").picked);
        CHECK([SGLyricsChosenSource(@"auto_pick") isEqualToString:@"musixmatch"]);

        // 8. Imported LRC and linked track lyrics are NEVER replaced by auto-select.
        [sg_answers removeAllObjects];
        sg_answers[@"importedLRC"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"importedLRC", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [sg_asked removeAllObjects];
        got = fetch(@"auto_imported");
        CHECK([got.provider isEqualToString:@"Imported LRC"] && [sg_asked isEqualToArray:@[@"importedLRC:auto_imported"]]);

        sg_linkedTrack = @"auto_linked";
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [sg_asked removeAllObjects];
        got = fetch(@"auto_linked");
        CHECK([got.provider isEqualToString:@"LRCLIB"] && [sg_asked isEqualToArray:@[@"lrclib:auto_linked"]]);
        sg_linkedTrack = nil;

        // 9. SGLyricsFetchSettled waits for the auto-select upgrade window instead of returning provisional lyrics.
        SGLyricsSetAutoSelectWindow(0.2);
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        sg_held = @"netease";
        __block SGLyricsResult *settledGot = nil;
        __block BOOL settledDone = NO;
        SGLyricsFetchSettled(@"auto_settled", ^(SGLyricsResult *result) { settledGot = result; settledDone = YES; });
        pump(^BOOL { return sg_release != nil; });
        CHECK(!settledDone);
        sg_held = nil;
        void (^releaseSettled)(void) = sg_release;
        sg_release = nil;
        releaseSettled();
        pump(^BOOL { return settledDone; });
        CHECK([settledGot.provider isEqualToString:@"NetEase"] && settledGot.wordTimed);

        // 10. Toggling SGKeyLyricsAutoSelect invalidates non-picked cached answers while keeping manual picks.
        SGLyricsSetAutoSelectWindow(0.2);
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"]}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        got = fetch(@"auto_toggle");
        CHECK([got.provider isEqualToString:@"LRCLIB"] && !got.wordTimed);
        // Flip switch on -> re-fetching the same track upgrades to word-timed instead of returning stale cache.
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [chosenNotes removeAllObjects];
        got = fetch(@"auto_toggle");
        CHECK([got.provider isEqualToString:@"LRCLIB"]);
        pump(^BOOL { return [chosenNotes containsObject:@"auto_toggle"]; });
        CHECK([fetch(@"auto_toggle").provider isEqualToString:@"NetEase"] && fetch(@"auto_toggle").wordTimed);
        // Manual pick on auto_pick survived the switch toggle.
        CHECK([fetch(@"auto_pick").provider isEqualToString:@"Musixmatch"] && fetch(@"auto_pick").picked);

        // 11. Word-timing-only source (NetEase, no page texts) publishes karaokeLines immediately for Redesigned
        //     without returning a text-less result to Native's waiting request, then merges LRCLIB's page texts.
        SGAnswer neteaseOnly = ^SGLyricsResult *{
            SGLyricsResult *r = wordLines(NO, NO, NO)();
            r.starts = nil;
            r.texts = nil;
            return r;
        };
        SGLyricsSetAutoSelectWindow(0.2);
        [sg_answers removeAllObjects];
        sg_answers[@"netease"] = neteaseOnly;
        sg_answers[@"lrclib"] = lines(YES);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"netease", @"lrclib"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [chosenNotes removeAllObjects];
        sg_held = @"lrclib";
        __block SGLyricsResult *mergedNetease = nil;
        __block BOOL neteaseFetchDone = NO;
        SGLyricsFetch(@"auto_netease_first", ^(SGLyricsResult *result) { mergedNetease = result; neteaseFetchDone = YES; });
        pump(^BOOL { return sg_release != nil && [chosenNotes containsObject:@"auto_netease_first"]; });
        // Redesigned already has NetEase's word-timed lines while LRCLIB is still in flight; Native wait is held.
        CHECK(SGKaraokeLinesForTrack(@"auto_netease_first").count > 0 && [SGLyricsCreditFor(@"auto_netease_first") isEqualToString:@"NetEase"]);
        CHECK(!neteaseFetchDone);
        sg_held = nil;
        void (^releaseLrclib)(void) = sg_release;
        sg_release = nil;
        releaseLrclib();
        pump(^BOOL { return neteaseFetchDone; });
        NSArray *ab = @[@"a", @"b", @""];
        CHECK([mergedNetease.provider isEqualToString:@"NetEase"] && mergedNetease.wordTimed);
        CHECK([mergedNetease.pageProvider isEqualToString:@"LRCLIB"] && [mergedNetease.texts isEqualToArray:ab]);

        // 12. NetEase upgrading LRCLIB keeps LRCLIB's uncensored page texts intact.
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = neteaseOnly;
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [chosenNotes removeAllObjects];
        got = fetch(@"auto_keep_uncensored");
        CHECK([got.provider isEqualToString:@"LRCLIB"] && [got.texts isEqualToArray:ab]);
        pump(^BOOL { return [chosenNotes containsObject:@"auto_keep_uncensored"]; });
        SGLyricsResult *keptUncensored = fetch(@"auto_keep_uncensored");
        CHECK([keptUncensored.provider isEqualToString:@"NetEase"] && keptUncensored.wordTimed);
        CHECK([keptUncensored.pageProvider isEqualToString:@"LRCLIB"] && [keptUncensored.texts isEqualToArray:ab]);

        // 13. Cache eviction (>40 tracks) during a batch does NOT discard pending in-window upgrades.
        SGLyricsSetAutoSelectWindow(0.3);
        [sg_answers removeAllObjects];
        sg_answers[@"lrclib"] = lines(YES);
        sg_answers[@"netease"] = wordLines(NO, NO, NO);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"lrclib", @"netease"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        sg_held = @"netease";
        __block SGLyricsResult *evictedGot = nil;
        __block BOOL evictedDone = NO;
        SGLyricsFetchSettled(@"auto_evict_target", ^(SGLyricsResult *result) { evictedGot = result; evictedDone = YES; });
        pump(^BOOL { return sg_release != nil; });
        void (^releaseEvicted)(void) = sg_release;
        sg_release = nil;
        sg_held = nil;
        // Fill cache past kKeptTracks (40) to evict auto_evict_target while its upgrade is pending.
        for (int i = 0; i < 45; i++) {
            fetch([NSString stringWithFormat:@"auto_evict_fill_%d", i]);
        }
        releaseEvicted();
        pump(^BOOL { return evictedDone; });
        CHECK([evictedGot.provider isEqualToString:@"NetEase"] && evictedGot.wordTimed);

        // 14. Changing language/romanization preferences invalidates non-picked cached answers under auto-select.
        SGLyricsSetAutoSelectWindow(0.2);
        [sg_answers removeAllObjects];
        sg_answers[@"musixmatch"] = wordLines(NO, NO, NO);
        sg_answers[@"binilyrics"] = wordLines(YES, YES, YES);
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"musixmatch", @"binilyrics"],
                                                                 SGKeyLyricsAutoSelect: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        got = fetch(@"auto_lang_change");
        CHECK([got.provider isEqualToString:@"Musixmatch"]);
        // Now enable romanization -> cache invalidates and re-fetch upgrades to BiniLyrics!
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLyricsProviders: @[@"musixmatch", @"binilyrics"],
                                                                 SGKeyLyricsAutoSelect: @YES,
                                                                 SGKeyLyricsRomanised: @YES}
                                                       forName:NSArgumentDomain];
        SGPrefsChanged();
        [chosenNotes removeAllObjects];
        got = fetch(@"auto_lang_change");
        CHECK([got.provider isEqualToString:@"Musixmatch"]);
        pump(^BOOL { return [chosenNotes containsObject:@"auto_lang_change"]; });
        CHECK([fetch(@"auto_lang_change").provider isEqualToString:@"BiniLyrics"]);

        [NSNotificationCenter.defaultCenter removeObserver:observer];
        SGLyricsSetAutoSelectWindow(2.5);

        printf("lyrics-walk: all checks passed\n");
    }
    return 0;
}
