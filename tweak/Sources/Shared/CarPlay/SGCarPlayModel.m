// Pure Objective-C model helpers for CarPlay lyrics windowing, Now Playing button merging,
// and control formatting. Shared between CarPlay.x and harness/carplay.
#import <CarPlay/CarPlay.h>
#import "CarPlay.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/SleepTimer.h"

@implementation SGCarPlayLyricEntry
@end

static NSString *displayTextForLine(SGKaraokeLine *line, BOOL japanese, BOOL romanised, BOOL romanisedReplace) {
    if (romanised && romanisedReplace) {
        SGKaraokeLine *rom = SGLyricsRomanisedLine(line, japanese);
        if (rom) {
            NSString *romText = SGKaraokeLineText(rom);
            if (romText.length) return romText;
        }
    }
    return SGKaraokeLineText(line) ?: @"";
}

static NSString *detailTextForLine(SGKaraokeLine *line, BOOL japanese, BOOL showTranslations, BOOL romanised, BOOL romanisedReplace) {
    if (showTranslations && line.translation.length) return line.translation;
    if (romanised && !romanisedReplace) {
        SGKaraokeLine *rom = SGLyricsRomanisedLine(line, japanese);
        if (rom) {
            NSString *romText = SGKaraokeLineText(rom);
            if (romText.length) return romText;
        }
    }
    return nil;
}

NSArray<SGCarPlayLyricEntry *> *SGCarPlayLyricsEntries(
    NSArray<SGKaraokeLine *> *lines,
    NSInteger positionMs,
    NSInteger delayMs,
    BOOL showTranslations,
    BOOL romanised,
    BOOL romanisedReplace,
    NSUInteger maxItems,
    NSInteger *outActiveIndex) {
    if (outActiveIndex) *outActiveIndex = -1;
    if (!lines.count || maxItems == 0) return @[];

    BOOL timed = SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone;
    BOOL japanese = SGLyricsLooksJapanese(lines);
    NSInteger adjusted = positionMs - delayMs;
    NSInteger active = timed ? SGKaraokeLeadLine(lines, adjusted) : -1;

    if (active >= 0) {
        BOOL nextFarOff = active + 1 == (NSInteger)lines.count || lines[active + 1].start - adjusted > SGKaraokeBreakMs;
        if (adjusted > SGKaraokeSungEnd(lines[active]) + SGKaraokeBreakMs && nextFarOff) {
            active = -1;
        }
    }
    if (outActiveIndex) *outActiveIndex = active;

    // Keep the active line near the top (1 line of prior context) so it stays visible in
    // CarPlay's ~3-row viewport and under Limited UI list caps while driving.
    NSUInteger count = lines.count;
    NSUInteger startIdx = 0;
    if (timed) {
        NSInteger anchor = active >= 0 ? active : SGKaraokeLeadLine(lines, adjusted);
        if (anchor > 1) startIdx = (NSUInteger)(anchor - 1);
    }
    NSUInteger endIdx = MIN(count, startIdx + maxItems);

    NSMutableArray<SGCarPlayLyricEntry *> *entries = [NSMutableArray arrayWithCapacity:endIdx - startIdx];
    for (NSUInteger i = startIdx; i < endIdx; i++) {
        SGKaraokeLine *line = lines[i];
        NSString *text = displayTextForLine(line, japanese, romanised, romanisedReplace);
        if (!text.length) continue;
        SGCarPlayLyricEntry *entry = [SGCarPlayLyricEntry new];
        entry.text = text;
        entry.detail = detailTextForLine(line, japanese, showTranslations, romanised, romanisedReplace);
        entry.startMs = line.start;
        entry.lineIndex = (NSInteger)i;
        entry.active = timed && (NSInteger)i == active;
        entry.seekable = timed;
        [entries addObject:entry];
    }
    return entries;
}

NSString *SGCarPlayNowPlayingLyricLine(
    NSArray<SGKaraokeLine *> *lines,
    NSInteger positionMs,
    NSInteger delayMs,
    BOOL showTranslation,
    BOOL romanised,
    BOOL romanisedReplace,
    NSInteger *outMsToChange) {
    if (outMsToChange) *outMsToChange = -1;
    if (!lines.count || SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) return nil;

    NSInteger adjusted = positionMs - delayMs;
    NSInteger index = SGKaraokeLeadLine(lines, adjusted);
    NSInteger ms = SGKaraokeMsToChange(lines, adjusted, index);
    if (outMsToChange) *outMsToChange = ms;
    if (index < 0) return nil;

    BOOL nextFarOff = index + 1 == (NSInteger)lines.count || lines[index + 1].start - adjusted > SGKaraokeBreakMs;
    if (adjusted > lines[index].end + SGKaraokeBreakMs && nextFarOff) return nil;

    SGKaraokeLine *line = lines[index];
    if (showTranslation && line.translation.length) return line.translation;
    BOOL japanese = SGLyricsLooksJapanese(lines);
    NSString *text = displayTextForLine(line, japanese, romanised, romanisedReplace);
    return text.length ? text : nil;
}

NSArray<CPNowPlayingButton *> *SGCarPlayMergedButtons(
    NSArray<CPNowPlayingButton *> *spotifyButtons,
    NSArray<CPNowPlayingButton *> *vitrineButtons,
    CPNowPlayingButton **outDisplacedMore) {
    if (outDisplacedMore) *outDisplacedMore = nil;
    NSArray<CPNowPlayingButton *> *base = spotifyButtons ?: @[];
    NSArray<CPNowPlayingButton *> *added = vitrineButtons ?: @[];
    if (!added.count) {
        return base.count <= SGCarPlayMaxButtons ? base : [base subarrayWithRange:NSMakeRange(0, SGCarPlayMaxButtons)];
    }

    NSUInteger maxAdded = MIN(added.count, SGCarPlayMaxButtons);
    NSArray<CPNowPlayingButton *> *trimmedAdded = added.count == maxAdded ? added : [added subarrayWithRange:NSMakeRange(0, maxAdded)];
    NSUInteger roomForBase = SGCarPlayMaxButtons - trimmedAdded.count;

    NSMutableArray<CPNowPlayingButton *> *merged = [NSMutableArray arrayWithCapacity:MIN(base.count + trimmedAdded.count, SGCarPlayMaxButtons)];
    if (base.count <= roomForBase) {
        [merged addObjectsFromArray:base];
    } else {
        // Keep Spotify's leading buttons and capture a displaced CPNowPlayingMoreButton if one existed.
        Class moreClass = NSClassFromString(@"CPNowPlayingMoreButton");
        NSMutableArray<CPNowPlayingButton *> *kept = [NSMutableArray arrayWithCapacity:roomForBase];
        for (CPNowPlayingButton *button in base) {
            if (moreClass && [button isKindOfClass:moreClass]) {
                if (outDisplacedMore && !*outDisplacedMore) *outDisplacedMore = button;
                continue;
            }
            if (kept.count < roomForBase) {
                [kept addObject:button];
            }
        }
        // If there's still room and we set aside a More button, put it back.
        if (outDisplacedMore && *outDisplacedMore && kept.count < roomForBase) {
            [kept addObject:*outDisplacedMore];
            *outDisplacedMore = nil;
        }
        [merged addObjectsFromArray:kept];
    }
    [merged addObjectsFromArray:trimmedAdded];
    return merged;
}

NSArray<NSNumber *> *SGCarPlaySpeedPresets(void) {
    return @[@0.75, @1.0, @1.25, @1.5, @2.0];
}

NSString *SGCarPlayFormatSpeed(double speed) {
    if (fabs(speed - round(speed * 10.0) / 10.0) < 0.005) {
        return [NSString stringWithFormat:@"%.1f×", speed];
    }
    return [NSString stringWithFormat:@"%.2f×", speed];
}

NSString *SGCarPlayFormatSleepTimer(NSInteger mode, NSDate *endDate, NSDate *now) {
    switch ((SGSleepTimerMode)mode) {
        case SGSleepTimerOff:
            return @"Off";
        case SGSleepTimerEndOfTrack:
            return @"End of track";
        case SGSleepTimerEndOfAlbum:
            return @"End of album";
        case SGSleepTimerAtTime: {
            if (!endDate) return @"On";
            NSTimeInterval left = [endDate timeIntervalSinceDate:(now ?: [NSDate date])];
            if (left <= 0) return @"Ending…";
            NSInteger mins = (NSInteger)ceil(left / 60.0);
            if (mins <= 1) return @"< 1 min left";
            return [NSString stringWithFormat:@"%ld min left", (long)mins];
        }
    }
    return @"Off";
}
