#import "HidePodcasts.h"

BOOL SGPodcastComponent(NSString *identifier, SGPodcastSurface surface) {
    if ([identifier hasPrefix:@"spotify:show:"] || [identifier hasPrefix:@"spotify:episode:"] ||
        [identifier isEqualToString:@"spotify:genre:podcasts-page"] ||
        [identifier isEqualToString:@"spotify:collection:your-episodes"] ||
        [identifier isEqualToString:@"spotify:collection:podcasts"]) return YES;

    switch (surface) {
        case SGPodcastHome:
            return [identifier isEqualToString:@"ActionCardCarouselElement"] ||
                   [identifier isEqualToString:@"Components.UI.EpisodeCard"] ||
                   [identifier isEqualToString:@"Components.UI.EpisodeCardVideo"] ||
                   [identifier isEqualToString:@"Components.UI.EpisodeCardActionsMedium"];
        case SGPodcastLibrary:
            return [identifier isEqualToString:@"Podcast.Row.Library"] ||
                   [identifier isEqualToString:@"NewEpisodes.Row.Library"] ||
                   [identifier isEqualToString:@"AddPodcast.Row.Library"] ||
                   [identifier isEqualToString:@"Components.UI.AddPodcastCardLibrary"];
        case SGPodcastSearch:
            return [identifier isEqualToString:@"Components.UI.ShowRowSearch"] ||
                   [identifier isEqualToString:@"Components.UI.AudioEpisodeRowSearch"] ||
                   [identifier isEqualToString:@"Components.UI.AudioEpisodeRowSearchOffline"] ||
                   [identifier isEqualToString:@"Components.UI.AudioEpisodeComplexRowSearch.AddButton"];
    }
    return NO;
}

BOOL SGPodcastHomeFilter(NSString *identifier) {
    if (![identifier hasPrefix:@"home-feed-"]) return NO;
    NSString *filter = [identifier substringFromIndex:@"home-feed-".length];
    return [filter isEqualToString:@"podcasts"] || [filter isEqualToString:@"podcasts-chip"] ||
           [filter isEqualToString:@"podcasts-following"] || [filter isEqualToString:@"podcasts-following-chip"];
}
