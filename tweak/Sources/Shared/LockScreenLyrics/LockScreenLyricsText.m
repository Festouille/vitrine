#import "LockScreenLyrics.h"
#import "Shared/Lyrics/Lyrics.h"

static const NSUInteger kMaxChars = 30;

NSString *SGLockScreenLyricText(SGKaraokeLine *line, NSInteger position, NSInteger *next) {
    NSUInteger length = SGKaraokeLineText(line).length;
    NSUInteger count = MAX((length + kMaxChars - 1) / kMaxChars, 1);
    NSUInteger target = (length + count - 1) / count;
    NSUInteger pieces = 1;
    NSMutableString *shown = [NSMutableString string];
    *next = -1;
    for (SGKaraokeWord *word in line.words) {
        if (word.start > position) {
            *next = word.start;
            break;
        }
        NSUInteger gap = shown.length && !word.joined ? 1 : 0;
        NSUInteger withWord = shown.length + gap + word.text.length;
        if (shown.length && (withWord > kMaxChars || (withWord > target && pieces < count))) {
            [shown setString:@""];
            pieces++;
            gap = 0;
        }
        if (gap) [shown appendString:@" "];
        [shown appendString:word.text ?: @""];
    }
    return shown.length ? shown : nil;
}
