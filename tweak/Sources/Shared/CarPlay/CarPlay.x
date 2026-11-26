// CarPlay hooks: live synced lyrics template, playback controls template, optional Now Playing lyric line
// while CarPlay is connected, and a sideload crash guard.
//
// Everything is gated behind SGKeyCarPlay (default OFF). When off, %ctor returns immediately and installs
// no hooks at all.
#import <CarPlay/CarPlay.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Settings/SGLocalize.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SleepTimer.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Sing/Sing.h"
#import "CarPlay.h"

static char kSGCarPlayButtonTagKey;
static const NSTimeInterval kCarPlayLyricsPollSec = 0.5;

static BOOL sg_cpConnected = NO;
static __weak CPInterfaceController *sg_cpInterface = nil;
static NSArray<CPNowPlayingButton *> *sg_cpSpotifyButtons = nil;
static CPNowPlayingButton *sg_cpDisplacedMore = nil;
static BOOL sg_cpUpdatingButtons = NO;

// Live Lyrics template state
static __weak CPListTemplate *sg_cpLyricsTemplate = nil;
static dispatch_source_t sg_cpLyricsTimer = nil;
static NSString *sg_cpLastRenderedTrackID = nil;
static NSInteger sg_cpLastRenderedActiveIdx = NSIntegerMin;
static NSUInteger sg_cpLastRenderedLineCount = NSUIntegerMax;
static BOOL sg_cpShowTranslations = YES;

// Controls template state
static __weak CPListTemplate *sg_cpControlsTemplate = nil;

// Optional CarPlay-only Now Playing lyric line (only when LockScreenLyrics is off)
static NSObject *sg_cpInfoLock = nil;
static NSDictionary *sg_cpSpotifyInfo = nil;
static CFAbsoluteTime sg_cpSpotifyInfoAt = 0;
static NSString *sg_cpShownNPLine = nil;
static BOOL sg_cpResendingInfo = NO;
static dispatch_source_t sg_cpNPTimer = nil;

#pragma mark - Helpers

static BOOL isVitrineButton(CPNowPlayingButton *button) {
    return button && [objc_getAssociatedObject(button, &kSGCarPlayButtonTagKey) boolValue];
}

static void markVitrineButton(CPNowPlayingButton *button) {
    if (button) objc_setAssociatedObject(button, &kSGCarPlayButtonTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIImage *carPlaySymbolImage(NSString *symbolName, CGFloat pointSize) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                                                         weight:UIImageSymbolWeightMedium];
    UIImage *sym = [UIImage systemImageNamed:symbolName withConfiguration:config];
    if (!sym) sym = [UIImage systemImageNamed:@"music.note" withConfiguration:config];
    if (!sym) return nil;
    // Rasterize SF Symbols into a plain bitmap so CarPlay's XPC template host never has to
    // resolve a CoreUI symbol catalog across processes.
    CGSize sz = sym.size;
    if (sz.width < 1 || sz.height < 1) sz = CGSizeMake(pointSize, pointSize);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    fmt.scale = 2.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:fmt];
    UIImage *rendered = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[sym imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal]
            drawInRect:(CGRect){CGPointZero, sz}];
    }];
    return [rendered imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static void stopTimer(dispatch_source_t __strong *timerPtr) {
    if (*timerPtr) {
        dispatch_source_cancel(*timerPtr);
        *timerPtr = nil;
    }
}

static BOOL templateIsOnStack(CPTemplate *tpl) {
    CPInterfaceController *ic = sg_cpInterface;
    if (!ic || !tpl) return NO;
    return [ic.templates containsObject:tpl];
}

#pragma mark - Live Lyrics Template

static void refreshLyricsTemplate(BOOL force);
static void scheduleLyricsTick(NSTimeInterval seconds);
static void pushControlsTemplate(void);

static void armLyricsTimerForCurrentTrack(void) {
    if (!sg_cpLyricsTemplate || !templateIsOnStack(sg_cpLyricsTemplate)) {
        stopTimer(&sg_cpLyricsTimer);
        return;
    }
    NSString *trackID = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = trackID.length ? SGKaraokeLinesForTrack(trackID) : nil;
    if (!lines.count || SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) {
        if (trackID.length && SGKaraokeLooking(trackID)) {
            scheduleLyricsTick(kCarPlayLyricsPollSec);
        } else {
            stopTimer(&sg_cpLyricsTimer);
        }
        return;
    }
    NSInteger pos = SGKaraokePositionMs();
    if (pos < 0) {
        scheduleLyricsTick(kCarPlayLyricsPollSec);
        return;
    }
    NSInteger adjusted = pos - SGKaraokeDelayMs();
    NSInteger idx = SGKaraokeLeadLine(lines, adjusted);
    NSInteger ms = SGKaraokeMsToChange(lines, adjusted, idx);
    if (ms > 0) {
        double speed = SGPlayerSpeed();
        if (speed <= 0.1) speed = 1.0;
        NSTimeInterval wait = MAX(0.1, ((ms + 15) / 1000.0) / speed);
        scheduleLyricsTick(MIN(wait, 5.0));
    } else {
        scheduleLyricsTick(1.0);
    }
}

static void scheduleLyricsTick(NSTimeInterval seconds) {
    if (!sg_cpLyricsTimer) {
        sg_cpLyricsTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sg_cpLyricsTimer, ^{
            refreshLyricsTemplate(NO);
        });
        dispatch_resume(sg_cpLyricsTimer);
    }
    dispatch_source_set_timer(sg_cpLyricsTimer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
        DISPATCH_TIME_FOREVER,
        25 * NSEC_PER_MSEC);
}

static void updateLyricsNavButtons(CPListTemplate *tpl, BOOL hasTranslations) {
    NSMutableArray<CPBarButton *> *buttons = [NSMutableArray array];
    if (hasTranslations) {
        NSString *title = sg_cpShowTranslations ? SGL(@"Original") : SGL(@"Translate");
        CPBarButton *transBtn = [[CPBarButton alloc] initWithTitle:title handler:^(CPBarButton *b) {
            sg_cpShowTranslations = !sg_cpShowTranslations;
            refreshLyricsTemplate(YES);
        }];
        [buttons addObject:transBtn];
    }
    if (SGFlag(SGKeyCarPlayControls, YES)) {
        CPBarButton *ctrlBtn = [[CPBarButton alloc] initWithTitle:SGL(@"Controls") handler:^(CPBarButton *b) {
            pushControlsTemplate();
        }];
        [buttons addObject:ctrlBtn];
    }
    tpl.trailingNavigationBarButtons = buttons;
}

static void refreshLyricsTemplate(BOOL force) {
    CPListTemplate *tpl = sg_cpLyricsTemplate;
    if (!tpl || !templateIsOnStack(tpl)) {
        stopTimer(&sg_cpLyricsTimer);
        return;
    }

    NSString *trackID = SGKaraokePlayingTrack();
    SPTPlayerState *state = SGPlayerState();
    NSString *trackTitle = state.track.trackTitle;

    if (!trackID.length) {
        if (force || sg_cpLastRenderedTrackID != nil) {
            sg_cpLastRenderedTrackID = nil;
            sg_cpLastRenderedActiveIdx = NSIntegerMin;
            sg_cpLastRenderedLineCount = 0;
            CPListItem *empty = [[CPListItem alloc] initWithText:SGL(@"Nothing playing")
                                                      detailText:SGL(@"Play a track in Spotify to see synced lyrics")];
            empty.enabled = NO;
            [tpl updateSections:@[[[CPListSection alloc] initWithItems:@[empty]]]];
            updateLyricsNavButtons(tpl, NO);
        }
        stopTimer(&sg_cpLyricsTimer);
        return;
    }

    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
    if (!lines) {
        SGKaraokeRequestLyrics(trackID);
        if (force || ![sg_cpLastRenderedTrackID isEqualToString:trackID] || sg_cpLastRenderedLineCount != 0) {
            sg_cpLastRenderedTrackID = [trackID copy];
            sg_cpLastRenderedActiveIdx = NSIntegerMin;
            sg_cpLastRenderedLineCount = 0;
            NSString *msg = SGKaraokeLooking(trackID) ? SGL(@"Loading lyrics…") : SGL(@"No lyrics for this track");
            CPListItem *status = [[CPListItem alloc] initWithText:msg detailText:trackTitle];
            status.enabled = NO;
            [tpl updateSections:@[[[CPListSection alloc] initWithItems:@[status]]]];
            updateLyricsNavButtons(tpl, NO);
        }
        armLyricsTimerForCurrentTrack();
        return;
    }

    if (!lines.count) {
        if (force || ![sg_cpLastRenderedTrackID isEqualToString:trackID] || sg_cpLastRenderedLineCount != 0) {
            sg_cpLastRenderedTrackID = [trackID copy];
            sg_cpLastRenderedActiveIdx = NSIntegerMin;
            sg_cpLastRenderedLineCount = 0;
            CPListItem *none = [[CPListItem alloc] initWithText:SGL(@"No lyrics for this track") detailText:trackTitle];
            none.enabled = NO;
            [tpl updateSections:@[[[CPListSection alloc] initWithItems:@[none]]]];
            updateLyricsNavButtons(tpl, NO);
        }
        stopTimer(&sg_cpLyricsTimer);
        return;
    }

    NSInteger pos = SGKaraokePositionMs();
    NSInteger delay = SGKaraokeDelayMs();
    BOOL romanised = SGFlag(SGKeyLyricsRomanised, NO);
    BOOL romanisedReplace = SGFlag(SGKeyLyricsRomanisedReplace, NO);
    NSUInteger maxItems = CPListTemplate.maximumItemCount;
    if (maxItems == 0 || maxItems > 48) maxItems = 48;

    NSInteger activeIdx = -1;
    NSArray<SGCarPlayLyricEntry *> *entries = SGCarPlayLyricsEntries(
        lines, pos, delay, sg_cpShowTranslations, romanised, romanisedReplace, maxItems, &activeIdx);

    // Avoid redundant CarPlay IPC updates when the active line hasn't moved.
    if (!force
        && [sg_cpLastRenderedTrackID isEqualToString:trackID]
        && sg_cpLastRenderedActiveIdx == activeIdx
        && sg_cpLastRenderedLineCount == entries.count) {
        armLyricsTimerForCurrentTrack();
        return;
    }

    sg_cpLastRenderedTrackID = [trackID copy];
    sg_cpLastRenderedActiveIdx = activeIdx;
    sg_cpLastRenderedLineCount = entries.count;

    NSMutableArray<CPListItem *> *items = [NSMutableArray arrayWithCapacity:entries.count];
    for (SGCarPlayLyricEntry *entry in entries) {
        CPListItem *item = [[CPListItem alloc] initWithText:entry.text detailText:entry.detail];
        item.playing = entry.active;
        item.playingIndicatorLocation = CPListItemPlayingIndicatorLocationLeading;
        if (entry.seekable) {
            NSInteger seekTarget = entry.startMs;
            item.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
                SGKaraokeSeek(seekTarget + SGKaraokeDelayMs());
                completionBlock();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    refreshLyricsTemplate(YES);
                });
            };
        } else {
            item.enabled = NO;
        }
        [items addObject:item];
    }

    NSString *header = trackTitle.length ? trackTitle : SGL(@"Synced Lyrics");
    CPListSection *section = [[CPListSection alloc] initWithItems:items header:header sectionIndexTitle:nil];
    [tpl updateSections:@[section]];
    updateLyricsNavButtons(tpl, SGKaraokeHasTranslations(lines));
    armLyricsTimerForCurrentTrack();
}

static void pushLyricsTemplate(void) {
    CPInterfaceController *ic = sg_cpInterface;
    if (!ic) return;
    if (sg_cpLyricsTemplate && templateIsOnStack(sg_cpLyricsTemplate)) {
        refreshLyricsTemplate(YES);
        return;
    }
    sg_cpShowTranslations = SGFlag(SGKeyCarPlayTranslations, YES);
    CPListTemplate *tpl = [[CPListTemplate alloc] initWithTitle:SGL(@"Lyrics") sections:@[]];
    sg_cpLyricsTemplate = tpl;
    sg_cpLastRenderedTrackID = nil;
    sg_cpLastRenderedActiveIdx = NSIntegerMin;
    sg_cpLastRenderedLineCount = NSUIntegerMax;
    [ic pushTemplate:tpl animated:YES completion:^(BOOL success, NSError *error) {
        if (success) {
            refreshLyricsTemplate(YES);
        } else {
            SGLog(@"carplay: push lyrics failed: %@", error.localizedDescription);
        }
    }];
}

#pragma mark - Controls Template

static void refreshControlsTemplate(void);

static void pushSpeedTemplate(void) {
    CPInterfaceController *ic = sg_cpInterface;
    if (!ic) return;
    double current = SGPlayerSpeed();
    NSMutableArray<CPListItem *> *items = [NSMutableArray array];
    for (NSNumber *n in SGCarPlaySpeedPresets()) {
        double speed = n.doubleValue;
        BOOL selected = fabs(current - speed) < 0.03;
        NSString *label = SGCarPlayFormatSpeed(speed);
        CPListItem *item = [[CPListItem alloc] initWithText:label
                                                 detailText:(selected ? SGL(@"Active") : nil)];
        item.playing = selected;
        item.playingIndicatorLocation = CPListItemPlayingIndicatorLocationTrailing;
        item.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
            SGSetPlayerSpeed(speed);
            completionBlock();
            [ic popTemplateAnimated:YES completion:^(BOOL ok, NSError *err) {
                refreshControlsTemplate();
            }];
        };
        [items addObject:item];
    }
    CPListSection *sec = [[CPListSection alloc] initWithItems:items];
    CPListTemplate *tpl = [[CPListTemplate alloc] initWithTitle:SGL(@"Playback Speed") sections:@[sec]];
    [ic pushTemplate:tpl animated:YES completion:nil];
}

static void pushSleepTimerTemplate(void) {
    CPInterfaceController *ic = sg_cpInterface;
    if (!ic) return;
    SGSleepTimerMode curMode = SGSleepTimerCurrentMode();

    struct { NSString *label; SGSleepTimerMode mode; NSTimeInterval sec; } presets[] = {
        { @"Off",          SGSleepTimerOff,        0 },
        { @"End of track", SGSleepTimerEndOfTrack, 0 },
        { @"15 minutes",   SGSleepTimerAtTime,     15 * 60 },
        { @"30 minutes",   SGSleepTimerAtTime,     30 * 60 },
        { @"45 minutes",   SGSleepTimerAtTime,     45 * 60 },
        { @"60 minutes",   SGSleepTimerAtTime,     60 * 60 },
    };

    NSMutableArray<CPListItem *> *items = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(presets) / sizeof(presets[0]); i++) {
        SGSleepTimerMode mode = presets[i].mode;
        NSTimeInterval sec = presets[i].sec;
        BOOL isCurrent = (mode == curMode && mode != SGSleepTimerAtTime);
        CPListItem *item = [[CPListItem alloc] initWithText:SGL(presets[i].label)
                                                 detailText:(isCurrent ? SGL(@"Active") : nil)];
        item.playing = isCurrent;
        item.playingIndicatorLocation = CPListItemPlayingIndicatorLocationTrailing;
        item.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
            SGSetSleepTimer(mode, sec);
            completionBlock();
            [ic popTemplateAnimated:YES completion:^(BOOL ok, NSError *err) {
                refreshControlsTemplate();
            }];
        };
        [items addObject:item];
    }
    CPListSection *sec = [[CPListSection alloc] initWithItems:items];
    CPListTemplate *tpl = [[CPListTemplate alloc] initWithTitle:SGL(@"Sleep Timer") sections:@[sec]];
    [ic pushTemplate:tpl animated:YES completion:nil];
}

static NSArray<CPListSection *> *buildControlsSections(void) {
    NSMutableArray<CPListItem *> *playbackItems = [NSMutableArray array];

    // Quick seek -15s / +15s
    CPListItem *back15 = [[CPListItem alloc] initWithText:SGL(@"Back 15 seconds")
                                               detailText:nil
                                                    image:carPlaySymbolImage(@"gobackward.15", 20)];
    back15.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
        NSInteger pos = SGKaraokePositionMs();
        if (pos >= 0) SGKaraokeSeek(MAX(0, pos - 15000));
        completionBlock();
    };
    [playbackItems addObject:back15];

    CPListItem *fwd15 = [[CPListItem alloc] initWithText:SGL(@"Forward 15 seconds")
                                              detailText:nil
                                                   image:carPlaySymbolImage(@"goforward.15", 20)];
    fwd15.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
        NSInteger pos = SGKaraokePositionMs();
        if (pos >= 0) SGKaraokeSeek(pos + 15000);
        completionBlock();
    };
    [playbackItems addObject:fwd15];

    // Playback speed
    NSString *speedText = SGCarPlayFormatSpeed(SGPlayerSpeed());
    CPListItem *speedItem = [[CPListItem alloc] initWithText:SGL(@"Playback Speed")
                                                  detailText:speedText
                                                       image:carPlaySymbolImage(@"gauge.with.needle", 20)
                                              accessoryImage:nil
                                               accessoryType:CPListItemAccessoryTypeDisclosureIndicator];
    speedItem.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
        completionBlock();
        pushSpeedTemplate();
    };
    [playbackItems addObject:speedItem];

    // Sleep timer
    NSString *timerText = SGCarPlayFormatSleepTimer(SGSleepTimerCurrentMode(), SGSleepTimerEnd(), [NSDate date]);
    CPListItem *timerItem = [[CPListItem alloc] initWithText:SGL(@"Sleep Timer")
                                                  detailText:SGL(timerText)
                                                       image:carPlaySymbolImage(@"moon.zzz", 20)
                                              accessoryImage:nil
                                               accessoryType:CPListItemAccessoryTypeDisclosureIndicator];
    timerItem.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
        completionBlock();
        pushSleepTimerTemplate();
    };
    [playbackItems addObject:timerItem];

    NSMutableArray<CPListItem *> *audioItems = [NSMutableArray array];

    // Karaoke / Vocals toggle (only when supported on this device)
    if (SGSingCurrentState() != SGSingStateUnavailable) {
        BOOL singOn = SGSingOn();
        CPListItem *singItem = [[CPListItem alloc] initWithText:SGL(@"Karaoke Vocals")
                                                     detailText:(singOn ? SGL(@"On") : SGL(@"Off"))
                                                          image:carPlaySymbolImage(singOn ? @"mic.fill" : @"mic", 20)];
        singItem.playing = singOn;
        singItem.playingIndicatorLocation = CPListItemPlayingIndicatorLocationTrailing;
        singItem.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
            SGSetSingOn(!SGSingOn());
            completionBlock();
            refreshControlsTemplate();
        };
        [audioItems addObject:singItem];
    }

    // Audio Effects / EQ master toggle
    BOOL dspOn = SGDSPSwitch(SGKeyDSP);
    CPListItem *dspItem = [[CPListItem alloc] initWithText:SGL(@"Audio Effects")
                                                detailText:(dspOn ? SGL(@"On") : SGL(@"Off"))
                                                     image:carPlaySymbolImage(@"slider.vertical.3", 20)];
    dspItem.playing = dspOn;
    dspItem.playingIndicatorLocation = CPListItemPlayingIndicatorLocationTrailing;
    dspItem.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
        SGDSPSetSwitch(SGKeyDSP, !SGDSPSwitch(SGKeyDSP));
        completionBlock();
        refreshControlsTemplate();
    };
    [audioItems addObject:dspItem];

    NSMutableArray<CPListSection *> *sections = [NSMutableArray array];
    [sections addObject:[[CPListSection alloc] initWithItems:playbackItems header:SGL(@"Playback") sectionIndexTitle:nil]];
    if (audioItems.count) {
        [sections addObject:[[CPListSection alloc] initWithItems:audioItems header:SGL(@"Sound") sectionIndexTitle:nil]];
    }
    CPNowPlayingButton *displacedMore = sg_cpDisplacedMore;
    if (displacedMore) {
        CPListItem *moreItem = [[CPListItem alloc] initWithText:SGL(@"More Options")
                                                     detailText:nil
                                                          image:carPlaySymbolImage(@"ellipsis.circle", 20)];
        moreItem.handler = ^(id<CPSelectableListItem> selectedItem, dispatch_block_t completionBlock) {
            completionBlock();
            CPNowPlayingButton *btn = sg_cpDisplacedMore;
            if (!btn) return;
            if ([btn respondsToSelector:@selector(handlePrimaryAction)]) {
                ((void (*)(id, SEL))objc_msgSend)(btn, @selector(handlePrimaryAction));
            } else {
                @try {
                    void (^handler)(CPNowPlayingButton *) = [btn valueForKey:@"handler"];
                    if (handler) handler(btn);
                } @catch (NSException *e) {
                    SGLog(@"carplay: displaced more handler failed: %@", e.reason);
                }
            }
        };
        [sections addObject:[[CPListSection alloc] initWithItems:@[moreItem] header:@"Spotify" sectionIndexTitle:nil]];
    }
    return sections;
}

static void refreshControlsTemplate(void) {
    CPListTemplate *tpl = sg_cpControlsTemplate;
    if (!tpl || !templateIsOnStack(tpl)) return;
    [tpl updateSections:buildControlsSections()];
}

static void pushControlsTemplate(void) {
    CPInterfaceController *ic = sg_cpInterface;
    if (!ic) return;
    if (sg_cpControlsTemplate && templateIsOnStack(sg_cpControlsTemplate)) {
        refreshControlsTemplate();
        return;
    }
    CPListTemplate *tpl = [[CPListTemplate alloc] initWithTitle:SGL(@"Vitrine Controls")
                                                       sections:buildControlsSections()];
    sg_cpControlsTemplate = tpl;
    [ic pushTemplate:tpl animated:YES completion:^(BOOL success, NSError *error) {
        if (!success) {
            SGLog(@"carplay: push controls failed: %@", error.localizedDescription);
        }
    }];
}

#pragma mark - Now Playing Buttons

static NSArray<CPNowPlayingButton *> *buildVitrineButtons(void) {
    NSMutableArray<CPNowPlayingButton *> *buttons = [NSMutableArray array];
    if (SGFlag(SGKeyCarPlayLyrics, YES)) {
        UIImage *img = carPlaySymbolImage(@"quote.bubble", 18);
        CPNowPlayingImageButton *lyricsBtn = [[CPNowPlayingImageButton alloc] initWithImage:img handler:^(CPNowPlayingButton *b) {
            pushLyricsTemplate();
        }];
        markVitrineButton(lyricsBtn);
        [buttons addObject:lyricsBtn];
    }
    if (SGFlag(SGKeyCarPlayControls, YES)) {
        UIImage *img = carPlaySymbolImage(@"slider.horizontal.3", 18);
        CPNowPlayingImageButton *ctrlBtn = [[CPNowPlayingImageButton alloc] initWithImage:img handler:^(CPNowPlayingButton *b) {
            pushControlsTemplate();
        }];
        markVitrineButton(ctrlBtn);
        [buttons addObject:ctrlBtn];
    }
    return buttons;
}

static void applyNowPlayingButtons(CPNowPlayingTemplate *tpl) {
    if (!tpl || sg_cpUpdatingButtons) return;
    NSArray<CPNowPlayingButton *> *base = sg_cpSpotifyButtons ?: @[];
    CPNowPlayingButton *displaced = nil;
    NSArray<CPNowPlayingButton *> *merged = SGCarPlayMergedButtons(base, buildVitrineButtons(), &displaced);
    sg_cpDisplacedMore = displaced;
    sg_cpUpdatingButtons = YES;
    [tpl updateNowPlayingButtons:merged];
    sg_cpUpdatingButtons = NO;
}

#pragma mark - CarPlay-only Now Playing Lyric Line (when Lock Screen Lyrics is off)

static BOOL carPlayNPLineActive(void) {
    return sg_cpConnected
        && SGFlag(SGKeyCarPlayNowPlayingLine, YES)
        && !SGFlag(SGKeyLockScreenLyrics, NO);
}

static double cpElapsedAt(NSDictionary *info, CFAbsoluteTime reportedAt, CFAbsoluteTime now) {
    NSNumber *reported = info[MPNowPlayingInfoPropertyPlaybackRate];
    double rate = reported ? reported.doubleValue : 1.0;
    return [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue] + rate * (now - reportedAt);
}

static BOOL cpPlayingBy(NSDictionary *info) {
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    return !rate || rate.doubleValue > 0;
}

static void cpTickNPLine(void);

static void cpScheduleNPTick(NSTimeInterval wait, NSDictionary *info) {
    if (wait < 0) {
        stopTimer(&sg_cpNPTimer);
        return;
    }
    if (!sg_cpNPTimer) {
        sg_cpNPTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sg_cpNPTimer, ^{
            cpTickNPLine();
        });
        dispatch_resume(sg_cpNPTimer);
    }
    NSNumber *rateNum = info[MPNowPlayingInfoPropertyPlaybackRate];
    double rate = rateNum.doubleValue > 0 ? rateNum.doubleValue : 1.0;
    NSTimeInterval seconds = MAX(0.1, wait / rate);
    dispatch_source_set_timer(sg_cpNPTimer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
        DISPATCH_TIME_FOREVER,
        20 * NSEC_PER_MSEC);
}

static NSDictionary *cpInfoWithLine(NSDictionary *info, NSString *line, double elapsed) {
    NSMutableDictionary *shown = [info mutableCopy];
    if (line.length) shown[MPMediaItemPropertyArtist] = line;
    shown[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
    return shown;
}

static void cpRestoreSpotifyInfo(void) {
    stopTimer(&sg_cpNPTimer);
    if (!sg_cpShownNPLine) return;
    sg_cpShownNPLine = nil;
    NSDictionary *info;
    CFAbsoluteTime reportedAt;
    @synchronized (sg_cpInfoLock) {
        info = sg_cpSpotifyInfo;
        reportedAt = sg_cpSpotifyInfoAt;
    }
    if (!info) return;
    double elapsed = cpElapsedAt(info, reportedAt, CFAbsoluteTimeGetCurrent());
    sg_cpResendingInfo = YES;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = cpInfoWithLine(info, nil, elapsed);
    sg_cpResendingInfo = NO;
}

static void cpTickNPLine(void) {
    if (!carPlayNPLineActive()) {
        cpRestoreSpotifyInfo();
        return;
    }
    NSDictionary *info;
    CFAbsoluteTime reportedAt;
    @synchronized (sg_cpInfoLock) {
        info = sg_cpSpotifyInfo;
        reportedAt = sg_cpSpotifyInfoAt;
    }
    if (!info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) return;

    SPTPlayerState *state = SGPlayerState();
    if (![state.track.trackTitle isEqualToString:info[MPMediaItemPropertyTitle]]) {
        cpScheduleNPTick(0.5, info);
        return;
    }
    NSString *trackID = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = trackID.length ? SGKaraokeLinesForTrack(trackID) : nil;
    if (!lines) {
        if (trackID.length) SGKaraokeRequestLyrics(trackID);
        cpScheduleNPTick(0.5, info);
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double elapsed = cpElapsedAt(info, reportedAt, now);
    NSInteger msToChange = -1;
    NSString *line = SGCarPlayNowPlayingLyricLine(
        lines,
        (NSInteger)(elapsed * 1000),
        SGKaraokeDelayMs(),
        SGFlag(SGKeyCarPlayTranslations, YES),
        SGFlag(SGKeyLyricsRomanised, NO),
        SGFlag(SGKeyLyricsRomanisedReplace, NO),
        &msToChange);
    cpScheduleNPTick(msToChange > 0 ? (msToChange + 10) / 1000.0 : -1, info);

    if (line == sg_cpShownNPLine || [line isEqualToString:sg_cpShownNPLine]) return;
    sg_cpShownNPLine = line;
    sg_cpResendingInfo = YES;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = cpInfoWithLine(info, line, elapsed);
    sg_cpResendingInfo = NO;
}

#pragma mark - CarPlay Connection Tracking

static void noteInterfaceController(CPInterfaceController *ic) {
    if (!ic) return;
    BOOL newlyConnected = !sg_cpConnected || sg_cpInterface != ic;
    sg_cpInterface = ic;
    sg_cpConnected = YES;
    if (newlyConnected) {
        SGLog(@"carplay: connected");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!sg_cpConnected) return;
            applyNowPlayingButtons(CPNowPlayingTemplate.sharedTemplate);
            if (carPlayNPLineActive()) cpTickNPLine();
        });
    }
}

static void noteDisconnected(void) {
    if (!sg_cpConnected) return;
    sg_cpConnected = NO;
    sg_cpInterface = nil;
    sg_cpLyricsTemplate = nil;
    sg_cpControlsTemplate = nil;
    stopTimer(&sg_cpLyricsTimer);
    cpRestoreSpotifyInfo();
    SGLog(@"carplay: disconnected");
}

#pragma mark - Player Observer

@interface SGCarPlayPlayerObserver : NSObject <SGPlayerStateObserver>
@end

@implementation SGCarPlayPlayerObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!sg_cpConnected) return;
    refreshLyricsTemplate(YES);
    refreshControlsTemplate();
}
@end

static SGCarPlayPlayerObserver *sg_cpPlayerObserver = nil;

#pragma mark - Hooks

%group SGCarPlayHooks

%hook CPInterfaceController

- (void)setRootTemplate:(__kindof CPTemplate *)rootTemplate animated:(BOOL)animated completion:(void (^)(BOOL, NSError *))completion {
    %orig;
    noteInterfaceController(self);
}

- (void)pushTemplate:(__kindof CPTemplate *)templateToPush animated:(BOOL)animated completion:(void (^)(BOOL, NSError *))completion {
    %orig;
    noteInterfaceController(self);
}

- (void)presentTemplate:(__kindof CPTemplate *)templateToPresent animated:(BOOL)animated completion:(void (^)(BOOL, NSError *))completion {
    %orig;
    noteInterfaceController(self);
}

%end

%hook CPNowPlayingTemplate

- (void)updateNowPlayingButtons:(NSArray<__kindof CPNowPlayingButton *> *)nowPlayingButtons {
    if (sg_cpUpdatingButtons) {
        %orig;
        return;
    }
    // Strip any previously injected Vitrine buttons so re-entrant updates stay idempotent.
    NSMutableArray<CPNowPlayingButton *> *spotifyOnly = [NSMutableArray arrayWithCapacity:nowPlayingButtons.count];
    for (CPNowPlayingButton *btn in nowPlayingButtons) {
        if (!isVitrineButton(btn)) [spotifyOnly addObject:btn];
    }
    sg_cpSpotifyButtons = [spotifyOnly copy];
    CPNowPlayingButton *displaced = nil;
    NSArray<CPNowPlayingButton *> *merged = SGCarPlayMergedButtons(sg_cpSpotifyButtons, buildVitrineButtons(), &displaced);
    sg_cpDisplacedMore = displaced;
    %orig(merged);
}

%end

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    if (sg_cpResendingInfo) {
        %orig;
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized (sg_cpInfoLock) {
        sg_cpSpotifyInfo = info;
        sg_cpSpotifyInfoAt = now;
    }
    if (!carPlayNPLineActive() || !info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
        %orig;
        return;
    }
    BOOL playing = cpPlayingBy(info);
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_cpShownNPLine = nil;
            cpScheduleNPTick(playing ? 0 : -1, info);
        });
        %orig;
        return;
    }
    SPTPlayerState *state = SGPlayerState();
    NSString *trackID = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = ([state.track.trackTitle isEqualToString:info[MPMediaItemPropertyTitle]] && trackID.length)
        ? SGKaraokeLinesForTrack(trackID) : nil;
    if (!lines) {
        if (trackID.length) SGKaraokeRequestLyrics(trackID);
        cpScheduleNPTick(playing ? 0.5 : -1, info);
        sg_cpShownNPLine = nil;
        %orig;
        return;
    }
    double elapsed = cpElapsedAt(info, now, now);
    NSInteger msToChange = -1;
    NSString *line = SGCarPlayNowPlayingLyricLine(
        lines,
        (NSInteger)(elapsed * 1000),
        SGKaraokeDelayMs(),
        SGFlag(SGKeyCarPlayTranslations, YES),
        SGFlag(SGKeyLyricsRomanised, NO),
        SGFlag(SGKeyLyricsRomanisedReplace, NO),
        &msToChange);
    cpScheduleNPTick(playing && msToChange > 0 ? (msToChange + 10) / 1000.0 : -1, info);
    sg_cpShownNPLine = line;
    %orig(cpInfoWithLine(info, line, elapsed));
}

- (NSDictionary *)nowPlayingInfo {
    if (carPlayNPLineActive()) {
        NSDictionary *info;
        @synchronized (sg_cpInfoLock) {
            info = sg_cpSpotifyInfo;
        }
        if (info) return info;
    }
    return %orig;
}

%end

%end

// Sideload crash guard: resigned Spotify installs can raise an NSException in CarPlay's Assistant Cell
// callbacks when SiriKit intents aren't entitled. Swallowing/catching keeps CarPlay alive.
%group SGCarPlayCrashFixIC
%hook CPInterfaceController
- (void)clientAssistantCellUnavailableWithError:(id)error {
    SGLog(@"carplay: swallowed clientAssistantCellUnavailableWithError: %@", error);
}
%end
%end

%group SGCarPlayCrashFixList
%hook CPListTemplate
- (void)setAssistantCellConfiguration:(id)config {
    @try {
        %orig;
    } @catch (NSException *ex) {
        SGLog(@"carplay: caught setAssistantCellConfiguration exception: %@", ex.reason);
    }
}
%end
%end

%ctor {
    if (!SGFlag(SGKeyCarPlay, NO)) return;

    sg_cpInfoLock = [NSObject new];
    sg_cpPlayerObserver = [SGCarPlayPlayerObserver new];
    SGAddPlayerStateObserver(sg_cpPlayerObserver);

    if (objc_getClass("CPInterfaceController") && objc_getClass("CPNowPlayingTemplate")) {
        %init(SGCarPlayHooks);
        if (SGFlag(SGKeyCarPlayCrashFix, YES)) {
            Class icCls = objc_getClass("CPInterfaceController");
            Class ltCls = objc_getClass("CPListTemplate");
            if (icCls && class_getInstanceMethod(icCls, @selector(clientAssistantCellUnavailableWithError:))) {
                %init(SGCarPlayCrashFixIC);
            }
            if (ltCls && class_getInstanceMethod(ltCls, @selector(setAssistantCellConfiguration:))) {
                %init(SGCarPlayCrashFixList);
            }
        }
    }

    // Track CarPlay scene connect/disconnect via UIScene notifications (queue:nil per AGENTS.md).
    [NSNotificationCenter.defaultCenter addObserverForName:UISceneWillConnectNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        Class cpSceneCls = NSClassFromString(@"CPTemplateApplicationScene");
        if (!cpSceneCls || ![note.object isKindOfClass:cpSceneCls]) return;
        CPTemplateApplicationScene *scene = (CPTemplateApplicationScene *)note.object;
        dispatch_async(dispatch_get_main_queue(), ^{
            noteInterfaceController(scene.interfaceController);
        });
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidDisconnectNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        Class cpSceneCls = NSClassFromString(@"CPTemplateApplicationScene");
        if (!cpSceneCls || ![note.object isKindOfClass:cpSceneCls]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            noteDisconnected();
        });
    }];

    // Refresh lyrics as soon as Karaoke delivers lines for the playing track.
    [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesKeptNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!sg_cpConnected) return;
            refreshLyricsTemplate(YES);
            if (carPlayNPLineActive()) cpTickNPLine();
        });
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesInvalidatedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!sg_cpConnected) return;
            refreshLyricsTemplate(YES);
        });
    }];

    SGLog(@"carplay: on (lyrics=%d controls=%d npLine=%d crashFix=%d)",
        SGFlag(SGKeyCarPlayLyrics, YES),
        SGFlag(SGKeyCarPlayControls, YES),
        SGFlag(SGKeyCarPlayNowPlayingLine, YES),
        SGFlag(SGKeyCarPlayCrashFix, YES));
}
