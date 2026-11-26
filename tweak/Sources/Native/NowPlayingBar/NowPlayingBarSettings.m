#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"

UIViewController *SGNowPlayingBarSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Now playing bar"
                                    intro:@"Hide the device button and Spotify's flags apply after you restart Spotify."
                                 sections:@[
        SGNotedSection(nil, @[
            SGOptionRow(@"Apple Music style polish", nil, SGKeyPlayerAMPolish),
        ], @"Adds press feedback to the mini player, smooths the handoff to and from the full player, "
           @"and follows the animated cover's colors behind the controls when available."),
        SGSection(nil, @[
            SGHideRow(@"Hide the device button", nil, SGHideBarConnect),
        ]),
        SGSection(@"Spotify's flags", @[
            SGFlagRow(@"Two lines of track info", @"ios-feature-nowplayingbar.two_lines_information_unit"),
            SGFlagRow(@"Save button", @"ios-feature-nowplayingbar.add_button"),
            SGFlagRow(@"Queue badge", @"ios-feature-nowplayingbar.queue_badge"),
            SGFlagRow(@"Hold and drag to resize", @"ios-feature-nowplayingbar.hold_and_drag_to_resize"),
            SGFlagRow(@"Video in the mini player", @"ios-feature-nowplaying.video_in_miniplayer"),
            SGFlagRow(@"Bar to cover art animation", @"ios-feature-nowplaying.bartocoverart_animation_enabled"),
            SGFlagRow(@"Mini player transition animations", @"ios-feature-nowplaying.miniplayer_transition_animations"),
        ]),
    ] footer:nil];
}
