#import "Core/SGCore.h"
#import "Core/SGFlagForce.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Navigation/Links.h"
#import "DefaultPlaylist.h"

static BOOL sg_active;

// Spotify 9.2.2 has its own playlist picker and track curation handler. Use those so the save
// follows the button's track, including on rows, and Spotify still owns the checkmark and removal.
static BOOL available(void) {
    return NSClassFromString(@"_TtC34DefaultSaveLocation_PickerPageImpl39DefaultSaveLocationPickerViewController") &&
           [NSClassFromString(@"_TtC33AlignedCuration_ConfigurationImpl28AlignedCurationConfiguration")
               instancesRespondToSelector:NSSelectorFromString(@"isDefaultSaveLocationCurationEnabled")];
}

__attribute__((constructor))
static void registerDefaultPlaylist(void) {
    if (!available()) return;
    NSSet<NSString *> *flags = [NSSet setWithArray:@[
        @"ios-feature-alignedcuration.default_save_location_curation_enabled",
        @"ios-feature-alignedcuration.track_curation_trait_enabled",
        @"ios-feature-defaultsavelocation.picker_page_enabled",
        @"ios-feature-defaultsavelocation.settings_entry_point_enabled",
    ]];
    sg_active = SGFlag(SGKeyDefaultPlaylist, NO);
    SGRegisterFlagForcer(YES, ^id(NSString *key) {
        return sg_active && [flags containsObject:key] ? @YES : nil;
    }, ^id(NSString *key) {
        return [flags containsObject:key] && SGFlag(SGKeyDefaultPlaylist, NO) ? @YES : nil;
    });
}

SGModSection *SGDefaultPlaylistSection(void) {
    if (!available()) return nil;
    SGModRow *toggle = SGOptionRow(@"Default playlist for +", @"Save tracks to the playlist you choose", SGKeyDefaultPlaylist);
    toggle.changed = ^(BOOL on) {
        if (on != sg_active) SGOfferRestart(@"Restart Spotify to change where the + button saves tracks.");
    };
    SGModRow *picker = SGActionRow(@"Choose default playlist", @"Open Spotify’s Default save locations", ^{
        NSURL *uri = [NSURL URLWithString:@"spotify:settings:default-save-locations"];
        if (SGSpotifyURIRoute(uri, NULL) != SGLinkRouteNone && SGOpenSpotifyURI(uri)) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Can’t open Default save locations"
            message:@"Try again when Spotify has finished loading." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    picker.visible = ^BOOL { return sg_active && SGFlag(SGKeyDefaultPlaylist, NO); };
    return SGNotedSection(@"Saving tracks", @[toggle, picker],
        @"After restarting, choose a music playlist in Spotify’s picker. Deselect Liked Songs there to save to your playlist only.");
}
