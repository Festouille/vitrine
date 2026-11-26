#import "PlayerShortcuts.h"
#import "PlayerState.h"
#import "Core/SGPrefs.h"
#import "Settings/SGLocalize.h"
#import "Shared/AudioEffects/AudioEffects.h"

UIMenu *SGQuickEQMenu(void) {
    if (!SGHidden(SGKeyPlayerShortcuts)) return nil;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    BOOL effectsOn = SGDSPSwitch(SGKeyDSP);
    BOOL eqOn;
    NSArray<NSNumber *> *gains = SGDSPEqualizerState(&eqOn);
    if (!effectsOn) {
        [items addObject:[UIAction actionWithTitle:SGL(@"Turn On Audio Effects") image:[UIImage systemImageNamed:@"power"]
                                       identifier:nil handler:^(UIAction *action) {
            if (SGHidden(SGKeyPlayerShortcuts)) SGDSPSetSwitch(SGKeyDSP, YES);
        }]];
    } else {
        UIAction *toggle = [UIAction actionWithTitle:SGL(eqOn ? @"Bypass EQ" : @"Enable EQ")
                                              image:[UIImage systemImageNamed:@"power"] identifier:nil handler:^(UIAction *action) {
            if (SGHidden(SGKeyPlayerShortcuts) && SGDSPSwitch(SGKeyDSP))
                SGDSPSetSwitch(SGKeyDSPEqualizer, !SGDSPSwitch(SGKeyDSPEqualizer));
        }];
        [items addObject:toggle];
        NSArray<NSString *> *names = SGDSPEqualizerPresetNames();
        NSMutableArray<UIMenuElement *> *presets = [NSMutableArray array];
        for (NSString *name in @[@"Flat", @"Bass", @"Treble", @"Vocal"]) {
            NSUInteger index = [names indexOfObject:name];
            if (index == NSNotFound) continue;
            NSArray<NSNumber *> *preset = SGDSPEqualizerPreset((NSInteger)index);
            if (!preset.count) continue;
            UIAction *item = [UIAction actionWithTitle:SGL(name) image:nil identifier:nil handler:^(UIAction *action) {
                if (!SGHidden(SGKeyPlayerShortcuts) || !SGDSPSwitch(SGKeyDSP)) return;
                SGDSPSetGains(SGKeyDSPEqualizerGains, preset);
                if (!SGDSPSwitch(SGKeyDSPEqualizer)) SGDSPSetSwitch(SGKeyDSPEqualizer, YES);
            }];
            item.state = eqOn && [gains isEqualToArray:preset] ? UIMenuElementStateOn : UIMenuElementStateOff;
            [presets addObject:item];
        }
        [items addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:presets]];
    }
    UIMenu *menu = [UIMenu menuWithTitle:SGL(@"Quick EQ") image:[UIImage systemImageNamed:@"slider.vertical.3"]
                             identifier:nil options:0 children:items];
    menu.subtitle = SGL(!effectsOn ? @"Audio Effects Off" : eqOn ? @"EQ On" : @"EQ Bypassed");
    return menu;
}

static UIAction *previewRow(NSString *title, NSString *artist) {
    UIAction *row = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *action) {}];
    row.attributes = UIMenuElementAttributesDisabled;
    row.subtitle = artist;
    return row;
}

UIMenu *SGPlayingNextMenu(void) {
    if (!SGHidden(SGKeyPlayerShortcuts)) return nil;
    SPTPlayerState *state = SGPlayerState();
    NSArray *future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    if (![future isKindOfClass:NSArray.class]) future = nil;
    NSMutableArray<UIAction *> *rows = [NSMutableArray array];
    for (SPTPlayerTrack *track in future) {
        id title = [track respondsToSelector:@selector(trackTitle)] ? track.trackTitle : nil;
        if (![title isKindOfClass:NSString.class] || ![title length]) continue;
        id artist = [track respondsToSelector:@selector(artistName)] ? track.artistName : nil;
        [rows addObject:previewRow(title, [artist isKindOfClass:NSString.class] ? artist : nil)];
        if (rows.count == 3) break;
    }
    NSString *empty = SGL(!future || future.count ? @"Queue Preview Unavailable" : @"No Upcoming Tracks");
    UIMenu *menu = [UIMenu menuWithTitle:SGL(@"Playing Next") image:[UIImage systemImageNamed:@"list.bullet"]
                            identifier:nil options:0 children:rows.count ? rows : @[previewRow(empty, nil)]];
    menu.subtitle = rows.count ? rows.firstObject.title : empty;
    return menu;
}
