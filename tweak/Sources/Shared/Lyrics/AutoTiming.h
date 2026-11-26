#import <Foundation/Foundation.h>

@class SGKaraokeLine;

#define SGKeyLyricsAutoTiming @"spotifyglass.lyricsAutoTiming"

NSArray<SGKaraokeLine *> *SGLyricsAutoTimedLines(NSString *track, NSArray<SGKaraokeLine *> *lines);
