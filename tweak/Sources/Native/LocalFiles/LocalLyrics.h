// The native look's viewer for an imported lyrics file (Shared/LocalFiles/LocalLyrics.h).
// The player's footer opens it even when Spotify has no lyrics affordance for the track.
//
//     LocalLyricsButton.x   the button on the footer, and has_lyrics for a linked local file
//     LocalLyricsPage.m     the page: the lines on black, following the song
#import <UIKit/UIKit.h>

// The page for whatever plays, full screen.
UIViewController *SGLocalLyricsPage(void);
