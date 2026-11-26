// Mod Settings' main page as App/ModSettings.x builds it, opened the way holding Home opens it
// (SGOpenModSettings), with the real App/Pages.m behind its Redesigned UI switch and the real Settings/
// framework, with stand-ins for Spotify runtime features. The launch line sets the look up and then plays
// actions, one every 0.9 s from 1 s in; screenshot after.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/ModSettingsHarness.app
//     xcrun simctl launch <udid> com.vitrine.modsettingsharness [setup...] [action...]
//
// Setup: redesign (Redesigned UI stored on), warning (a red environment row at the top), lang=fr/es/tr/device,
// keep (the stored look and language stay; otherwise they are cleared first).
// Actions: toggle=<section>.<row> (that row's switch flipped the way a tap does), cancel (the alert that
// switch brings up closed with Later), bottom (scrolled to the end), dump (the rows of each section and
// what each reads beside its chevron, to the log), gated (a page of a switch, ten rows, a headed and noted
// section of twelve rows shown only while the switch is on, and a row that comes by itself), later (that row
// let come; the page's ticker brings it), top (scrolled to the start), layout (the scroll offset, and each
// section's rows and heading and note heights, to the log), needs (the Lock screen artwork section below iOS
// 26), tap=<section>.<row> (that row selected, and the alert it brings up logged), rows (the row the mod adds to
// Spotify's settings list and drawer, after each list is emptied of its subviews, counted to the log).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "App/About/About.h"
#import "App/SettingsPresets.h"
#import "Core/SGCore.h"
#import "Settings/SGLocalize.h"
#import "Settings/SGPage.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Player/RepeatMode.h"

BOOL SGHarnessRepeatAction(NSString *verb, NSString *value, UIViewController *page);

// Spotify's page protocol, so SGRegisterPages finds one and the page is pushed as on the phone.
@protocol SPTPageController <NSObject>
@end

BOOL SGHarnessWarning;
BOOL SGHarnessOnboarding;

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

// With `rows` on the launch line, Spotify's settings list controller and the side drawer's list by their own
// names, made before ModSettings.x's %ctor hooks them (constructor priorities hold within this binary).
static const char *const kDrawerClass = "_TtC23SideDrawer_ListPageImplP33_1D8CA7A9CC41E8D184AF8B9AAE4E684E28SideDrawerListCollectionView";
static const char *const kSettingsClass = "_TtC21Settings_PlatformImpl26SettingsListViewController";

__attribute__((constructor(101))) static void harnessClasses(void) {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"rows"]) return;
    objc_registerClassPair(objc_allocateClassPair(UICollectionView.class, kDrawerClass, 0));
    objc_registerClassPair(objc_allocateClassPair(UIViewController.class, kSettingsClass, 0));
}

// The `gated` page: a switch, ten rows of filler, then a headed and noted section whose twelve rows show only
// while the switch is on, and a row that comes by itself once `later` is played.
static BOOL sg_later;
static NSString *const kGate = @"spotifyglass.harness.gate";

static UIViewController *gatedPage(void) {
    SGSetEnabled(kGate, NO);
    NSMutableArray<SGModRow *> *filler = [NSMutableArray array], *gated = [NSMutableArray array];
    for (int i = 0; i < 10; i++) [filler addObject:SGStatRow([NSString stringWithFormat:@"Filler %d", i + 1], ^NSString *{ return @"-"; })];
    for (int i = 0; i < 12; i++) {
        SGModRow *row = SGStatRow([NSString stringWithFormat:@"Gated %d", i + 1], ^NSString *{ return @"on"; });
        row.visible = ^BOOL { return SGFlag(kGate, NO); };
        [gated addObject:row];
    }
    SGModRow *later = SGStatRow(@"Came by itself", ^NSString *{ return @"later"; });
    later.visible = ^BOOL { return sg_later; };
    return [[SGModPage alloc] initWithTitle:@"Gated" intro:nil sections:@[
        SGSection(@"Gate", [@[SGOptionRow(@"Show the gated rows", nil, kGate)] arrayByAddingObjectsFromArray:filler]),
        SGNotedSection(@"Gated", gated, @"A note under the gated rows, which goes with them."),
        SGSection(@"Later", @[later]),
    ] footer:nil];
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSLog(@"[harness] page protocol %@", NSStringFromProtocol(@protocol(SPTPageController)));
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    if (![args containsObject:@"keep"]) {
        SGSetEnabled(SGKeyRedesign, NO);
        SGSetEnabled(SGKeyRedesignUntested, NO);
        SGSetEnabled(SGKeySettingsTranslate, NO);
        SGSetInt(SGKeySettingsLanguage, SGSettingsLanguageDevice);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySettingsThemes];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySettingsTheme];
        SGPrefsChanged();
    }
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if ([arg isEqualToString:@"redesign"]) SGSetEnabled(SGKeyRedesign, YES);
        else if ([arg isEqualToString:@"warning"]) SGHarnessWarning = YES;
        else if ([arg hasPrefix:@"lang="]) {
            NSUInteger language = [@[@"device", @"fr", @"es", @"tr"] indexOfObject:[arg substringFromIndex:5]];
            NSAssert(language != NSNotFound, @"Unknown harness language");
            SGSetEnabled(SGKeySettingsTranslate, YES);
            SGSetInt(SGKeySettingsLanguage, (NSInteger)language);
        }
        else if (![arg isEqualToString:@"keep"]) [actions addObject:arg];
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIViewController *home = [UIViewController new];
    home.view.backgroundColor = UIColor.blackColor;
    self.nav = [[UINavigationController alloc] initWithRootViewController:home];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ SGOpenModSettings(home.view); });

    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.9 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", [action hasPrefix:@"preset-input="] ? @"preset-input" : action);
            [self run:action];
        });
    }];
    return YES;
}

- (UITableView *)table {
    return ((UITableViewController *)self.nav.topViewController).tableView;
}

- (NSIndexPath *)pathFrom:(NSString *)text {
    NSArray<NSString *> *at = [text componentsSeparatedByString:@"."];
    return [NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue];
}

- (void)tapTitle:(NSString *)title {
    UITableView *table = self.table;
    for (NSInteger section = 0; section < table.numberOfSections; section++) {
        for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
            if ([[(UIListContentConfiguration *)cell.contentConfiguration text] isEqualToString:title]) {
                [table.delegate tableView:table didSelectRowAtIndexPath:path];
                return;
            }
        }
    }
    NSAssert(NO, @"Missing row: %@", title);
}

- (void)run:(NSString *)action {
    if ([action isEqualToString:@"pause"]) return;
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if (SGHarnessRepeatAction(verb, value, self.nav.topViewController)) {
        return;
    } else if ([verb isEqualToString:@"theme"]) {
        BOOL light = [value isEqualToString:@"light"];
        UITraitCollection *traits = table.traitCollection;
        NSAssert(self.nav.topViewController.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark,
                 @"The experiment must override the table, not the controller");
        NSAssert(traits.userInterfaceStyle == (light ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark),
                 @"Expected %@ on %@, got %ld (scene %ld)", value, self.nav.topViewController.title,
                 (long)traits.userInterfaceStyle, (long)self.window.windowScene.traitCollection.userInterfaceStyle);
        UIColor *background = [table.backgroundColor resolvedColorWithTraitCollection:traits];
        CGFloat white = -1;
        NSAssert([background getWhite:&white alpha:NULL] && (light ? white > 0.85 : white < 0.10),
                 @"Wrong table color on %@: %@", self.nav.topViewController.title, background);
        UITableViewCell *firstCell = table.visibleCells.firstObject;
        UIListContentConfiguration *content = (UIListContentConfiguration *)firstCell.contentConfiguration;
        if ([content isKindOfClass:UIListContentConfiguration.class] && ![content.text isEqualToString:@"Warning"]) {
            UIColor *ink = [content.textProperties.color resolvedColorWithTraitCollection:traits];
            UIColor *card = [firstCell.backgroundColor resolvedColorWithTraitCollection:traits];
            CGFloat inkWhite = -1, cardWhite = -1;
            NSAssert([ink getWhite:&inkWhite alpha:NULL] && [card getWhite:&cardWhite alpha:NULL] &&
                     (light ? inkWhite < 0.15 && cardWhite > 0.85 : inkWhite > 0.85 && cardWhite < 0.20),
                     @"Low contrast on '%@', ink %@ against %@", content.text, ink, card);
        }
        NSLog(@"[harness] theme passed: %@ %@", self.nav.topViewController.title, value);
    } else if ([verb isEqualToString:@"restart-pending"]) {
        SGSetEnabled(SGKeyHideVideoSwitch, !SGHidden(SGKeyHideVideoSwitch));
    } else if ([verb isEqualToString:@"restart-contrast"]) {
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        findViews(table.tableHeaderView, UIButton.class, buttons);
        UIButton *pill = buttons.firstObject;
        NSAssert(pill.window && [pill.configuration.title hasPrefix:@"Restart to apply"], @"Missing restart pill");
        UIColor *ink = [pill.titleLabel.textColor resolvedColorWithTraitCollection:pill.traitCollection];
        CGFloat white = -1;
        BOOL light = [value isEqualToString:@"light"];
        NSAssert([ink getWhite:&white alpha:NULL] && (light ? white < 0.15 : white > 0.85),
                 @"Unreadable restart label in %@ with a black custom accent: %@", value, ink);
        NSLog(@"[harness] restart contrast passed: %@", value);
    } else if ([verb isEqualToString:@"theme-off"]) {
        UISwitch *toggle = (UISwitch *)[table cellForRowAtIndexPath:[self pathFrom:@"0.0"]].accessoryView;
        NSAssert([toggle isKindOfClass:UISwitch.class] && !toggle.isOn && [table numberOfRowsInSection:0] == 1,
                 @"The experiment must be off and hide the theme picker");
        NSLog(@"[harness] experiment is off");
    } else if ([verb isEqualToString:@"theme-menu"]) {
        UIButton *menu = (UIButton *)[table cellForRowAtIndexPath:[self pathFrom:@"0.1"]].accessoryView;
        NSAssert([menu isKindOfClass:UIButton.class], @"Missing theme menu");
        UIAction *choice = nil;
        for (UIAction *item in menu.menu.children) if ([item.title isEqualToString:value]) choice = item;
        NSAssert(choice, @"Unknown theme choice %@", value);
        [choice performWithSender:menu target:nil];
    } else if ([verb isEqualToString:@"back"]) {
        [self.nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"remember-repeat"]) {
        UIViewController *page = self.nav.topViewController;
        if (![page.title isEqualToString:SGL(@"Player")]) {
            [self tapTitle:SGL(@"Player")];
            page = self.nav.topViewController;
            table = self.table;
        }
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
                UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
                if (![[(UIListContentConfiguration *)cell.contentConfiguration text] isEqualToString:SGL(@"Remember repeat mode")]) continue;
                [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
                [table layoutIfNeeded];
                UISwitch *toggle = (UISwitch *)([table cellForRowAtIndexPath:path] ?: cell).accessoryView;
                NSAssert([toggle isKindOfClass:UISwitch.class], @"Missing Remember repeat mode switch");
                if ([value isEqualToString:@"toggle"]) {
                    [toggle setOn:!toggle.isOn animated:NO];
                    [toggle sendActionsForControlEvents:UIControlEventValueChanged];
                } else {
                    NSAssert(toggle.isOn == value.boolValue && SGFlag(SGKeyRememberRepeatMode, NO) == value.boolValue,
                             @"Remember repeat mode setting does not match %@", value);
                    NSLog(@"[harness] Remember repeat mode switch: %@", toggle.isOn ? @"on" : @"off");
                }
                return;
            }
        }
        NSAssert(NO, @"Missing Remember repeat mode row");
    } else if ([verb isEqualToString:@"toggle"]) {
        NSMutableArray<UIControl *> *controls = [NSMutableArray array];
        findViews([table cellForRowAtIndexPath:[self pathFrom:value]].accessoryView, UIControl.class, controls);
        UIControl *toggle = nil;
        for (UIControl *control in controls) if ([control respondsToSelector:@selector(setOn:animated:)]) toggle = control;
        if (!toggle) { NSLog(@"[harness] no switch at %@", value); return; }
        [(id)toggle setOn:![(id)toggle isOn] animated:YES];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    } else if ([verb isEqualToString:@"search-gate"]) {
        SGSetEnabled(@"spotifyglass.harness.searchGate", value.boolValue);
    } else if ([verb isEqualToString:@"search"]) {
        [self tapTitle:SGL(@"Search Mod Settings")];
    } else if ([verb isEqualToString:@"query"]) {
        UISearchBar *bar = (UISearchBar *)table.tableHeaderView;
        NSAssert([bar isKindOfClass:UISearchBar.class], @"Missing settings search field");
        [bar.delegate searchBar:bar textDidChange:value];
    } else if ([verb isEqualToString:@"pick"]) {
        [self tapTitle:value];
    } else if ([verb isEqualToString:@"page-title"]) {
        NSAssert([self.nav.topViewController.title isEqualToString:value], @"Unexpected settings page title");
        NSLog(@"[harness] settings page title matched %@", value);
    } else if ([verb isEqualToString:@"search-count"]) {
        NSAssert([table numberOfRowsInSection:0] == value.integerValue, @"Unexpected number of settings search results");
        NSLog(@"[harness] gated settings search matched %@ rows as expected", value);
    } else if ([verb isEqualToString:@"search-result"]) {
        BOOL found = NO;
        for (NSInteger row = 0; row < [table numberOfRowsInSection:0]; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
            UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
            found |= [[(UIListContentConfiguration *)cell.contentConfiguration text] isEqualToString:value];
        }
        NSAssert(found, @"Missing settings search result: %@", value);
        NSLog(@"[harness] settings search found %@", value);
    } else if ([verb isEqualToString:@"localized"]) {
        NSAssert([SGL(@"Appearance") isEqualToString:value], @"Unexpected settings translation");
        NSAssert(SGL(nil) == nil && [SGL(@"") isEqualToString:@""], @"Missing text did not stay empty");
        NSAssert([SGL(@"A string without a translation") isEqualToString:@"A string without a translation"],
                 @"Unknown text did not fall back to English");
        NSInteger language = SGInt(SGKeySettingsLanguage, SGSettingsLanguageDevice);
        if (SGFlag(SGKeySettingsTranslate, NO)) {
            SGSetInt(SGKeySettingsLanguage, -1);
            NSAssert([SGL(@"Appearance") isEqualToString:@"Appearance"], @"Invalid language did not fall back to English");
            SGSetInt(SGKeySettingsLanguage, language);
        }
        NSLog(@"[harness] localization and fallback checks passed: %@", value);
    } else if ([verb isEqualToString:@"jumped"]) {
        NSAssert([self.nav.topViewController.title isEqualToString:@"Gradient"], @"Search did not open the owning page");
        NSAssert([[self.nav.viewControllers[self.nav.viewControllers.count - 2] title] isEqualToString:@"Home & Library"],
                 @"Search did not preserve the destination's parent page");
        NSIndexPath *target = [NSIndexPath indexPathForRow:0 inSection:0];
        NSAssert([table.indexPathsForVisibleRows containsObject:target], @"Search target is not visible");
        NSLog(@"[harness] nested settings search passed");
    } else if ([verb isEqualToString:@"preset-check"]) {
        NSUInteger skipped = 0;
        NSDictionary *import = SGReadPresetJSON(@"{\"settings\":{\"spotifyglass.hide.videoSwitch\":true,\"spotifyglass.adblock.ads\":true,\"spotifyglass.hide.fullScreenCover\":3}}", &skipped);
        NSAssert([import isEqualToDictionary:@{SGKeyHideVideoSwitch:@YES}] && skipped == 2,
                 @"Preset import accepted an unsupported key or a non-Boolean value");
        NSAssert(!SGReadPresetJSON(@"[]", NULL), @"Preset import accepted an array");
        BOOL before = SGHidden(SGKeyHideVideoSwitch);
        SGSetEnabled(SGKeyHideVideoSwitch, !before);
        NSAssert([SGPendingRestartSettings() containsObject:@"Hide Switch to video"], @"Missing pending restart setting");
        SGSetEnabled(SGKeyHideVideoSwitch, before);
        NSAssert(![SGPendingRestartSettings() containsObject:@"Hide Switch to video"], @"Reverted change is still pending");
        NSLog(@"[harness] preset import and pending restart checks passed");
    } else if ([verb isEqualToString:@"preset-input"]) {
        NSMutableArray<UITextView *> *inputs = [NSMutableArray array];
        findViews([table cellForRowAtIndexPath:[self pathFrom:@"0.0"]].contentView, UITextView.class, inputs);
        NSAssert(inputs.count == 1, @"Missing preset JSON input");
        inputs.firstObject.text = [action isEqualToString:verb] ? @"" : [action substringFromIndex:verb.length + 1];
    } else if ([verb isEqualToString:@"cancel"]) {
        UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
        if (![alert isKindOfClass:UIAlertController.class]) return;
        NSLog(@"[harness] alert \"%@\": %@", alert.title, alert.message);
        [alert dismissViewControllerAnimated:YES completion:nil];
    } else if ([verb isEqualToString:@"bottom"]) {
        [table setContentOffset:CGPointMake(0, MAX(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom)) animated:NO];
    } else if ([verb isEqualToString:@"gated"]) {
        [self.nav pushViewController:gatedPage() animated:NO];
    } else if ([verb isEqualToString:@"rows"]) {
        // The row ModSettings.x adds to Spotify's settings list and to the side drawer's list, each emptied of its
        // subviews afterward as Spotify can do, then laid out again.
        NSUInteger (^count)(UIView *) = ^NSUInteger(UIView *list) {
            NSUInteger n = 0;
            for (UIView *sub in list.subviews) n += [NSStringFromClass(sub.class) isEqualToString:@"SGModSettingsRow"];
            return n;
        };
        void (^empty)(UIView *) = ^(UIView *list) {
            for (UIView *sub in [list.subviews copy]) [sub removeFromSuperview];
            [list setNeedsLayout];
            [list layoutIfNeeded];
        };
        UICollectionView *drawer = [[NSClassFromString(@(kDrawerClass)) alloc] initWithFrame:CGRectMake(0, 0, 390, 600)
                                                                         collectionViewLayout:[UICollectionViewFlowLayout new]];
        [self.window addSubview:drawer];
        [drawer layoutIfNeeded];
        NSUInteger drawerFirst = count(drawer);
        empty(drawer);
        UIViewController *settings = [NSClassFromString(@(kSettingsClass)) new];
        UICollectionView *list = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 390, 600) collectionViewLayout:[UICollectionViewFlowLayout new]];
        [settings.view addSubview:list];
        [settings viewDidLayoutSubviews];
        [list layoutIfNeeded];
        NSUInteger settingsFirst = count(list);
        empty(list);
        NSLog(@"[harness] rows: drawer %lu on its first layout, %lu after it was emptied; settings %lu, %lu after it was emptied",
              (unsigned long)drawerFirst, (unsigned long)count(drawer), (unsigned long)settingsFirst, (unsigned long)count(list));
        [drawer removeFromSuperview];
    } else if ([verb isEqualToString:@"needs"]) {
        [self.nav pushViewController:[[SGModPage alloc] initWithTitle:@"Lock screen" intro:nil sections:@[
            SGSection(@"Lock screen artwork", @[SGLockScreenArtworkNeedsRow()]),
        ] footer:nil] animated:NO];
    } else if ([verb isEqualToString:@"tap"]) {
        NSIndexPath *path = [self pathFrom:value];
        [table.delegate tableView:table didSelectRowAtIndexPath:path];
        UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
        if ([alert isKindOfClass:UIAlertController.class]) NSLog(@"[harness] alert \"%@\": %@", alert.title, alert.message);
    } else if ([verb isEqualToString:@"top"]) {
        [table setContentOffset:CGPointMake(0, -table.adjustedContentInset.top) animated:NO];
    } else if ([verb isEqualToString:@"signing-onboarding"]) {
        SGHarnessOnboarding = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 66 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (SGIsAlertController(SGTopController())) {
                NSLog(@"[harness] signing onboarding: FAIL; alert while onboarding was open");
                exit(EXIT_FAILURE);
            }
            SGHarnessOnboarding = NO;
            NSLog(@"[harness] signing onboarding: cleared after 66 seconds without an alert");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self run:@"signing=profile"];
            });
        });
    } else if ([verb isEqualToString:@"signing"]) {
        UIViewController *top = SGTopController();
        UIAlertController *alert = [top isKindOfClass:UIAlertController.class] ? (UIAlertController *)top : nil;
        BOOL shown = [alert.title isEqualToString:@"Spotify signing expires soon"];
        BOOL passed = [value isEqualToString:@"profile"]
            ? shown && [alert.message containsString:@"provisioning profile"]
            : !shown && SGEnabled(SGKeySigningExpiryReminder) == [value isEqualToString:@"quiet"];
        NSLog(@"[harness] signing %@: %@; %@", value, passed ? @"PASS" : @"FAIL", alert.message ?: @"no alert");
        exit(passed ? EXIT_SUCCESS : EXIT_FAILURE);
    } else if ([verb isEqualToString:@"later"]) {
        sg_later = YES;
    } else if ([verb isEqualToString:@"layout"]) {
        UIEdgeInsets inset = table.adjustedContentInset;
        NSLog(@"[harness] offset %.0f of room %.0f", table.contentOffset.y + inset.top, table.bounds.size.height - inset.top - inset.bottom);
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSLog(@"[harness] section %ld: %ld rows, heading %.0f pt, note %.0f pt", (long)section, (long)[table numberOfRowsInSection:section],
                  [table rectForHeaderInSection:section].size.height, [table rectForFooterInSection:section].size.height);
        }
    } else if ([verb isEqualToString:@"dump"]) {
        NSLog(@"[harness] Redesigned UI stored %d", SGRedesignedUIStored());
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
                UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                findViews(cell.accessoryView, UILabel.class, labels);
                NSString *text = [(UIListContentConfiguration *)cell.contentConfiguration text];
                [rows addObject:labels.count ? [NSString stringWithFormat:@"%@ [%@]", text, labels.firstObject.text] : text];
            }
            NSLog(@"[harness] section %ld: %@", (long)section, [rows componentsJoinedByString:@", "]);
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
