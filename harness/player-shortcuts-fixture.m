#import <Foundation/Foundation.h>
#import "Shared/AudioEffects/AudioEffectsApply.h"

@interface SGFixtureQueueTrack : NSObject
@property (nonatomic, copy) NSString *trackTitle, *artistName;
@end
@implementation SGFixtureQueueTrack
@end

NSArray *SGFixtureUpcomingTracks(void) {
    NSMutableArray *tracks = [NSMutableArray array];
    for (NSArray *entry in @[@[@"Night Drive", @"Mira Vale"], @[@"Blue Hour", @"Glass Atlas"],
                             @[@"First Light", @"Mira Vale"], @[@"Afterglow", @"Glass Atlas"]]) {
        SGFixtureQueueTrack *track = [SGFixtureQueueTrack new];
        track.trackTitle = entry[0];
        track.artistName = entry[1];
        [tracks addObject:track];
    }
    return tracks;
}

void SGDSPApply(NSString *effect) {}
