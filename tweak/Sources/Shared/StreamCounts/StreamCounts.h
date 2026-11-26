#import <UIKit/UIKit.h>

#define SGKeyStreamCounts @"spotifyglass.streamCounts"

NSString *SGStreamCountTrackURI(UIView *cell, BOOL album);
NSString *SGStreamCountText(NSString *uri, id observer, dispatch_block_t changed);
NSNumber *SGStreamCountInReply(NSData *reply, NSString *uri);
void SGStreamCountRememberDataLoader(id factory);
