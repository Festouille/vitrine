#import <Foundation/Foundation.h>

#define SGKeyHidePodcasts @"spotifyglass.hidePodcasts"

typedef NS_ENUM(NSUInteger, SGPodcastSurface) {
    SGPodcastHome,
    SGPodcastLibrary,
    SGPodcastSearch,
};

BOOL SGPodcastComponent(NSString *identifier, SGPodcastSurface surface);
BOOL SGPodcastHomeFilter(NSString *identifier);
