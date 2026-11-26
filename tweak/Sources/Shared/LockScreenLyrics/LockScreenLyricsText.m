#import "LockScreenLyrics.h"
#import "Shared/Lyrics/Lyrics.h"

static const NSUInteger kMaxChars = 30;

static NSUInteger wordStart(NSArray<SGKaraokeWord *> *words, NSUInteger end, BOOL timed, NSUInteger *length) {
    NSUInteger start = end - 1;
    *length = words[start].text.length;
    while (timed && start > 0 && words[start].joined &&
        !SGKaraokeUnspacedScript(words[start].text) && !SGKaraokeUnspacedScript(words[start - 1].text)) {
        *length += words[--start].text.length;
    }
    return start;
}

NSString *SGLockScreenLyricText(SGKaraokeLine *line, NSInteger position, NSInteger *next) {
    NSArray<SGKaraokeWord *> *words = line.words;
    NSUInteger end = 0;
    while (end < words.count && words[end].start <= position) end++;
    *next = end < words.count ? words[end].start : -1;
    if (!end) return nil;

    BOOL timed = line.timing == SGKaraokeTimingWords;
    NSUInteger length;
    NSUInteger start = wordStart(words, end, timed, &length);
    while (start > 0) {
        NSUInteger extra;
        NSUInteger previous = wordStart(words, start, timed, &extra);
        extra += words[start].joined ? 0 : 1;
        if (length + extra > kMaxChars) break;
        length += extra;
        start = previous;
    }
    NSMutableString *shown = [NSMutableString stringWithCapacity:length];
    for (NSUInteger i = start; i < end; i++) {
        if (shown.length && !words[i].joined) [shown appendString:@" "];
        [shown appendString:words[i].text ?: @""];
    }
    return shown.length ? shown : nil;
}
