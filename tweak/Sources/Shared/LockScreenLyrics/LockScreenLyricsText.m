#import "LockScreenLyrics.h"
#import "Shared/Lyrics/Lyrics.h"

static const NSUInteger kMaxChars = 30;

NSString *SGLockScreenLyricText(SGKaraokeLine *line, NSInteger position, NSInteger *next) {
    NSArray<SGKaraokeWord *> *words = line.words;
    NSUInteger end = 0;
    while (end < words.count && words[end].start <= position) end++;
    *next = end < words.count ? words[end].start : -1;
    if (!end) return nil;

    NSUInteger start = end - 1;
    NSUInteger length = words[start].text.length;
    while (start > 0) {
        NSUInteger extra = words[start - 1].text.length + (words[start].joined ? 0 : 1);
        if (length + extra > kMaxChars) break;
        length += extra;
        start--;
    }
    NSMutableString *shown = [NSMutableString stringWithCapacity:length];
    for (NSUInteger i = start; i < end; i++) {
        if (shown.length && !words[i].joined) [shown appendString:@" "];
        [shown appendString:words[i].text ?: @""];
    }
    return shown.length ? shown : nil;
}
