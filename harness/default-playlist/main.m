#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/DefaultPlaylist/DefaultPlaylist.h"
#import "Shared/Navigation/Links.h"

@interface _TtC33AlignedCuration_ConfigurationImpl28AlignedCurationConfiguration : NSObject
- (BOOL)isDefaultSaveLocationCurationEnabled;
@end

@implementation _TtC33AlignedCuration_ConfigurationImpl28AlignedCurationConfiguration
- (BOOL)isDefaultSaveLocationCurationEnabled {
    return [SGForcedFlagValue(@"ios-feature-alignedcuration.default_save_location_curation_enabled") boolValue];
}
@end

@interface _TtC34DefaultSaveLocation_PickerPageImpl39DefaultSaveLocationPickerViewController : SGModPage
@end

@implementation _TtC34DefaultSaveLocation_PickerPageImpl39DefaultSaveLocationPickerViewController
@end

static NSURL *pickerURI;
static BOOL chosen;
static NSString *savedTo;

void SGDressPageBar(UIViewController *page) {}
void SGUndressPageBar(UIViewController *page) {}
void SGPlacePageBar(UIViewController *page) {}

SGLinkRoute SGSpotifyURIRoute(NSURL *uri, NSString **via) {
    return ([uri.absoluteString isEqualToString:@"spotify:settings:default-save-locations"] &&
        [SGForcedFlagValue(@"ios-feature-defaultsavelocation.picker_page_enabled") boolValue] &&
        [SGForcedFlagValue(@"ios-feature-defaultsavelocation.settings_entry_point_enabled") boolValue])
        ? SGLinkRouteOpens : SGLinkRouteNone;
}

BOOL SGOpenSpotifyURI(NSURL *uri) {
    if (SGSpotifyURIRoute(uri, NULL) != SGLinkRouteOpens) return NO;
    pickerURI = uri;
    SGModRow *liked = SGActionRow(@"Liked Songs", nil, ^{ chosen = NO; });
    liked.checked = ^BOOL { return !chosen; };
    SGModRow *playlist = SGActionRow(@"Road Trip", nil, ^{ chosen = YES; });
    playlist.checked = ^BOOL { return chosen; };
    UIViewController *picker = [[_TtC34DefaultSaveLocation_PickerPageImpl39DefaultSaveLocationPickerViewController alloc]
        initWithTitle:@"Default save locations" intro:@"Spotify picker fixture" sections:@[SGSection(@"Music", @[liked, playlist])] footer:nil];
    [(UINavigationController *)SGTopController() pushViewController:picker animated:NO];
    return YES;
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@property (nonatomic, strong) UILabel *result;
@end

@implementation AppDelegate
- (void)selectRow:(NSInteger)row onPage:(SGModPage *)page {
    [page.tableView.delegate tableView:page.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
}

- (void)tapPlus {
    BOOL explicitSave = [[_TtC33AlignedCuration_ConfigurationImpl28AlignedCurationConfiguration new] isDefaultSaveLocationCurationEnabled] &&
        [SGForcedFlagValue(@"ios-feature-alignedcuration.track_curation_trait_enabled") boolValue];
    savedTo = explicitSave && chosen ? @"Road Trip" : @"Liked Songs";
    self.result.text = [NSString stringWithFormat:@"Saved to %@ only", savedTo];
}

- (void)showPlayer {
    UIViewController *player = [UIViewController new];
    player.title = SGRedesignedUI() ? @"Redesigned player fixture" : @"Native player fixture";
    player.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *track = [UILabel new];
    track.text = @"Test Track";
    track.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    UIButton *plus = [UIButton buttonWithType:UIButtonTypeSystem];
    [plus setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    plus.accessibilityIdentifier = @"Components.UI.AddToButton";
    [plus addTarget:self action:@selector(tapPlus) forControlEvents:UIControlEventTouchUpInside];
    self.result = [UILabel new];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[track, plus, self.result]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 20;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [player.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:player.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:player.view.centerYAnchor],
    ]];
    [self.nav pushViewController:player animated:NO];
    [plus sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray *args = NSProcessInfo.processInfo.arguments;
    BOOL enabled = [args containsObject:@"enabled"];
    SGModSection *section = SGDefaultPlaylistSection();
    NSCAssert(section && !section.rows[0].defaultOn, @"option defaults off");
    NSCAssert(section.rows[1].visible() == enabled, @"picker appears only in enabled launch");
    NSCAssert(!SGForcedFlagValue(@"unrelated"), @"unrelated flags untouched");
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    SGModPage *settings = [[SGModPage alloc] initWithTitle:@"Player" intro:nil sections:@[section] footer:nil];
    self.nav = [[UINavigationController alloc] initWithRootViewController:settings];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([args containsObject:@"toggle"]) {
            UITableViewCell *cell = [settings.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            UISwitch *toggle = (UISwitch *)cell.accessoryView;
            NSCAssert([toggle isKindOfClass:UISwitch.class] && !toggle.isOn, @"stock switch is present and off");
            toggle.on = YES;
            [toggle sendActionsForControlEvents:UIControlEventValueChanged];
            NSCAssert(SGFlag(SGKeyDefaultPlaylist, NO) && !section.rows[1].visible(), @"stored switch waits for restart");
            SGSetEnabled(SGKeyDefaultPlaylist, NO);
            NSLog(@"[harness] settings switch toggled; picker waits for restart");
            return;
        }
        if ([args containsObject:@"settings"]) {
            NSLog(@"[harness] %@ settings: switch %@, picker %@", SGRedesignedUI() ? @"redesigned" : @"native",
                  enabled ? @"on" : @"off", enabled ? @"shown" : @"hidden");
            return;
        }
        if (enabled) {
            [self selectRow:1 onPage:settings];
            NSCAssert(pickerURI != nil, @"the settings row dispatches Spotify's picker URI");
            SGModPage *picker = (SGModPage *)self.nav.topViewController;
            [self selectRow:1 onPage:picker];
            [picker.tableView reloadData];
            NSCAssert(chosen, @"playlist selected in picker fixture");
            NSLog(@"[harness] picker routed to %@; Road Trip selected", pickerURI.absoluteString);
            if ([args containsObject:@"picker"]) return;
        }
        [self showPlayer];
        NSCAssert([savedTo isEqualToString:enabled ? @"Road Trip" : @"Liked Songs"], @"unexpected plus destination");
        NSLog(@"[harness] %@ player: + saved to %@ only", SGRedesignedUI() ? @"redesigned" : @"native", savedTo);
    });
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
