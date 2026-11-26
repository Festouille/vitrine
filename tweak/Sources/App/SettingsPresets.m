#import "Core/SGCore.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Home/Home.h"
#import "Native/Player/NowPlaying.h"
#import "Redesigned/Home/Home.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Player/Player.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGLocalize.h"
#import "Shared/Lossless/SGLossless.h"
#import "Shared/Player/PlayerSettings.h"
#import "Pages.h"
#import "SettingsPresets.h"

typedef NS_OPTIONS(NSUInteger, SGProfile) {
    SGMinimalNative = 1 << 0,
    SGMinimalRedesign = 1 << 1,
    SGCleanNative = 1 << 2,
    SGCleanRedesign = 1 << 3,
};

static const struct {
    NSString *key;
    NSString *title;
    SGProfile profiles;
    BOOL defaultOn;
    BOOL presetOn;
} kSettings[] = {
    {SGKeyRedesign, @"Redesigned UI"},
    {SGKeyAmoled, @"AMOLED background"},
    {SGRKeyPlainCheck, @"Plain checkmark"},
    {SGKeyLossless, @"Lossless files"},
    {SGKeyHideVideoSwitch, @"Hide Switch to video", SGMinimalNative | SGMinimalRedesign, NO, YES},
    {SGKeyHideFullScreenCover, @"Hide full screen cover", SGMinimalNative | SGMinimalRedesign, NO, YES},
    {SGHideRelatedVideos, @"Hide related videos on Player", SGMinimalNative, NO, YES},
    {SGHideRecommendations, @"Hide recommendations on Player", SGMinimalNative, NO, YES},
    {SGRKeyPlayerHideShuffle, @"Hide Shuffle on Player", SGMinimalRedesign, NO, YES},
    {SGRKeyPlayerHideRepeat, @"Hide Repeat on Player", SGMinimalRedesign, NO, YES},
    {SGHideHomePills, @"Hide Home filter pills", SGCleanNative, NO, YES},
    {SGHideHomeShortcuts, @"Hide Home shortcuts grid", SGCleanNative, NO, YES},
    {SGHideHomePreviews, @"Hide Home preview cards", SGCleanNative, NO, YES},
    {SGRKeyHomeTopPicks, @"Show Home Top picks", SGCleanRedesign, YES, NO},
    {SGRKeyHomeHideShortcuts, @"Hide Home shortcuts", SGCleanRedesign, NO, YES},
};

static const NSUInteger kSettingCount = sizeof kSettings / sizeof *kSettings;
static NSDictionary<NSString *, NSNumber *> *sg_launchSettings;

static BOOL currentValue(NSUInteger index) {
    NSString *key = kSettings[index].key;
    return [key isEqualToString:SGKeyRedesign] ? SGRedesignedUIStored() : SGFlag(key, kSettings[index].defaultOn);
}

void SGRememberLaunchSettings(void) {
    if (sg_launchSettings) return;
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < kSettingCount; i++) settings[kSettings[i].key] = @(currentValue(i));
    sg_launchSettings = [settings copy];
}

NSArray<NSString *> *SGPendingRestartSettings(void) {
    if (!sg_launchSettings) return @[];
    NSMutableArray *pending = [NSMutableArray array];
    for (NSUInteger i = 0; i < kSettingCount; i++) {
        NSString *key = kSettings[i].key;
        BOOL before = [key isEqualToString:SGKeyRedesign] ? SGRedesignedUI() : sg_launchSettings[key].boolValue;
        if (before != currentValue(i)) [pending addObject:kSettings[i].title];
    }
    return pending;
}

NSDictionary<NSString *, NSNumber *> *SGReadPresetJSON(NSString *json, NSUInteger *skipped) {
    if (skipped) *skipped = 0;
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length || data.length > 128 * 1024) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *settings = object[@"settings"] ?: object;
    if (![settings isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *accepted = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < kSettingCount; i++) {
        NSString *key = kSettings[i].key;
        id value = settings[key];
        if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) continue;
        if ([key isEqualToString:SGKeyRedesign] && [value boolValue] && !SGRedesignAvailable()) continue;
        accepted[key] = value;
    }
    if (skipped) *skipped = settings.count - accepted.count;
    return [accepted copy];
}

static NSDictionary<NSString *, NSNumber *> *preset(NSString *name) {
    BOOL redesigned = SGRedesignedUIStored();
    BOOL stock = [name isEqualToString:@"Stock"];
    SGProfile profile = [name isEqualToString:@"Minimal player"] ? (redesigned ? SGMinimalRedesign : SGMinimalNative)
                                                                 : (redesigned ? SGCleanRedesign : SGCleanNative);
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < kSettingCount; i++) {
        NSString *key = kSettings[i].key;
        if (stock) {
            if (kSettings[i].profiles || [key isEqualToString:SGKeyRedesign]) {
                settings[key] = @(kSettings[i].defaultOn && !SGHidden(SGKeyStock));
            }
        } else if (kSettings[i].profiles & profile) {
            settings[key] = @(kSettings[i].presetOn);
        }
    }
    return settings;
}

static void preview(NSString *title, NSDictionary<NSString *, NSNumber *> *settings, NSUInteger skipped) {
    NSMutableDictionary<NSString *, NSNumber *> *changes = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < kSettingCount; i++) {
        NSString *key = kSettings[i].key;
        NSNumber *after = settings[key];
        BOOL before = currentValue(i);
        if (!after || after.boolValue == before) continue;
        changes[key] = after;
        [lines addObject:[NSString stringWithFormat:@"%@: %@ → %@", SGL(kSettings[i].title), SGL(before ? @"On" : @"Off"), SGL(after.boolValue ? @"On" : @"Off")]];
    }
    if (lines.count) [lines addObject:SGL(@"\nRestart Spotify to apply.")];
    else [lines addObject:SGL(@"No settings would change.")];
    if (skipped) [lines addObject:[NSString stringWithFormat:SGL(@"\nIgnored %lu unsupported or invalid entries."), (unsigned long)skipped]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(title)
        message:[lines componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleAlert];
    if (changes.count) {
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"Apply") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [changes enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *value, BOOL *stop) {
                if ([key isEqualToString:SGKeyRedesign]) SGSetRedesignedUI(value.boolValue);
                else SGSetEnabled(key, value.boolValue);
            }];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:SGL(changes.count ? @"Cancel" : @"OK") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

@interface SGImportPresetPage : SGPage
@end

@implementation SGImportPresetPage {
    UITextView *_input;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Import preset";
    self.tableView.tableHeaderView = SGNote(@"Paste a JSON settings object. Only supported appearance, Home and player controls can be imported.");
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _input = [UITextView new];
    _input.backgroundColor = SGCardBackground();
    _input.textColor = UIColor.labelColor;
    _input.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _input.adjustsFontForContentSizeCategory = YES;
    _input.autocorrectionType = UITextAutocorrectionTypeNo;
    _input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _input.smartQuotesType = UITextSmartQuotesTypeNo;
    _input.accessibilityLabel = SGL(@"Preset JSON");
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, self.tableView.tableHeaderView, 16, 0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 0 ? 160 : UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, path.section ? @"preview" : @"input");
    if (path.section) {
        SGFillCell(cell, @"Preview changes", nil, nil, nil);
        cell.accessoryView = SGChevronView();
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        _input.frame = CGRectInset(cell.contentView.bounds, 8, 8);
        _input.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [cell.contentView addSubview:_input];
    }
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (!path.section) return;
    [table deselectRowAtIndexPath:path animated:YES];
    [_input resignFirstResponder];
    NSUInteger skipped;
    NSDictionary *settings = SGReadPresetJSON(_input.text, &skipped);
    if (settings) {
        preview(@"Import changes", settings, skipped);
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"Invalid preset")
        message:SGL(@"Paste a JSON object containing settings, up to 128 KB.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

static SGModRow *presetRow(NSString *title, NSString *subtitle) {
    return SGActionRow(title, subtitle, ^{ preview(title, preset(title), 0); });
}

SGModRow *SGSettingsPresetsRow(void) {
    return SGWithTile(SGPageRow(@"Presets", ^UIViewController *{
        return [[SGModPage alloc] initWithTitle:@"Presets" intro:@"Preview each preset before applying it." sections:@[
            SGSection(nil, @[
                presetRow(@"Minimal player", @"Hide secondary player controls and cards"),
                presetRow(@"Clean Home", @"Simplify Home in the selected look"),
                presetRow(@"Stock", @"Use the native look and restore the controls managed by these presets"),
            ]),
            SGSection(nil, @[SGPageRow(@"Import preset", ^UIViewController *{
                return [[SGImportPresetPage alloc] initWithStyle:UITableViewStyleInsetGrouped];
            })]),
        ] footer:nil];
    }), @"square.on.square", UIColor.systemTealColor);
}

@implementation SGModSettingsPage {
    UIButton *_restartPill;
    UIView *_restartHeader;
    id _defaultsObserver;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _restartHeader = [UIView new];
    _restartPill = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = UIButtonConfiguration.tintedButtonConfiguration;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    UIColor *darkMark = SGAccentMark();
    configuration.baseForegroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleLight ? UIColor.blackColor : darkMark;
    }];
    _restartPill.configuration = configuration;
    [_restartPill addTarget:self action:@selector(showRestartChanges) forControlEvents:UIControlEventTouchUpInside];
    [_restartHeader addSubview:_restartPill];
    __weak SGModSettingsPage *weak = self;
    _defaultsObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weak updateRestartPill]; });
        }];
}

- (void)dealloc {
    if (_defaultsObserver) [NSNotificationCenter.defaultCenter removeObserver:_defaultsObserver];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateRestartPill];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (self.tableView.tableHeaderView != _restartHeader) return;
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [_restartPill sizeThatFits:CGSizeMake(MAX(0, width - 32), CGFLOAT_MAX)];
    size.width = MIN(size.width, MAX(0, width - 32));
    _restartPill.frame = CGRectMake((width - size.width) / 2, 8, size.width, size.height);
    CGSize headerSize = CGSizeMake(width, size.height + 16);
    if (CGSizeEqualToSize(_restartHeader.bounds.size, headerSize)) return;
    _restartHeader.frame = (CGRect){CGPointZero, headerSize};
    self.tableView.tableHeaderView = _restartHeader;
}

- (void)updateRestartPill {
    NSArray<NSString *> *pending = SGPendingRestartSettings();
    if (!pending.count) {
        if (self.tableView.tableHeaderView) self.tableView.tableHeaderView = nil;
        return;
    }
    NSString *title = [NSString stringWithFormat:SGL(@"Restart to apply (%lu)"), (unsigned long)pending.count];
    if (![_restartPill.configuration.title isEqualToString:title]) {
        UIButtonConfiguration *configuration = _restartPill.configuration;
        configuration.title = title;
        _restartPill.configuration = configuration;
    }
    if (!self.tableView.tableHeaderView) self.tableView.tableHeaderView = _restartHeader;
}

- (void)showRestartChanges {
    NSArray<NSString *> *pending = SGPendingRestartSettings();
    if (pending.count) {
        NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:pending.count];
        for (NSString *name in pending) [names addObject:SGL(name)];
        SGOfferRestart([NSString stringWithFormat:SGL(@"Changes to apply:\n\n%@\n\nSpotify will close. Open it again to apply these settings."),
                        [names componentsJoinedByString:@"\n"]]);
    }
    [self updateRestartPill];
}

@end
