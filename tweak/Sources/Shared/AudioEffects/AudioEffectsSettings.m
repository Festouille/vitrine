// The audio effects' settings: what each key holds until set, its bounds, and the lists the page's choices
// pick from, in the order the engine numbers them (SGDSPEffects.h).
#import "Core/SGCore.h"
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"
#import <os/lock.h>

const double SGDSPEqualizerFrequencies[15] = {25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000};
const double SGDSPEqualizerGainLimit = 12;
const double SGDSPCompanderFrequencies[7] = {95, 200, 400, 800, 1600, 3400, 7500};
const double SGDSPCompanderGainLimit = 1;

#pragma mark - the keys

typedef struct {
    NSString *__unsafe_unretained key;
    SGDSPRange range;
} SGDSPNumberKey;

static const SGDSPNumberKey kNumbers[] = {
    {SGKeyDSPPostGain,          {-12, 12, 0, 0.5}},
    {SGKeyDSPLimiterThreshold,  {-24, 0, -0.3, 0.1}},
    {SGKeyDSPLimiterRelease,    {10, 500, 100, 5}},
    {SGKeyDSPCompanderTime,     {0.05, 0.5, 0.2, 0.01}},
    {SGKeyDSPBassGain,          {1, 15, 6, 0.5}},
    {SGKeyDSPConvolverMode,     {0, 2, 0, 1}},
    {SGKeyDSPReverbPreset,      {0, 8, 5, 1}},     // Plate
    {SGKeyDSPReverbAmount,      {0, 100, 50, 1}},  // the room's own mix
    {SGKeyDSPStereoWideLevel,   {0, 100, 60, 1}},
    {SGKeyDSPCrossfeedMode,     {0, 2, 2, 1}},     // libbs2b's own default
    {SGKeyDSPTubeDrive,         {0, 18, 4, 0.5}},
};

static NSDictionary<NSString *, NSString *> *stringDefaults(void) {
    static NSDictionary<NSString *, NSString *> *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{
            SGKeyDSPCompanderGains: @"0;0;0;0;0;0;0",
            SGKeyDSPEqualizerGains: @"0;0;0;0;0;0;0;0;0;0;0;0;0;0;0",
            SGKeyDSPGraphicEqNodes: @"GraphicEQ: 0.0 0.0;",
            SGKeyDSPGraphicEqHeadphone: @"",
            SGKeyDSPConvolverFile: @"",
            SGKeyDSPDDCFile: @"",
            SGKeyDSPLiveprogFile: @"",
        };
    });
    return defaults;
}

// The switches of the effects, each the prefix of its own keys' names.
static NSArray<NSString *> *effectSwitches(void) {
    return @[SGKeyDSPCompander, SGKeyDSPBass, SGKeyDSPEqualizer, SGKeyDSPGraphicEq, SGKeyDSPConvolver, SGKeyDSPDDC,
             SGKeyDSPLiveprog, SGKeyDSPReverb, SGKeyDSPStereoWide, SGKeyDSPCrossfeed, SGKeyDSPTube];
}

NSString *SGDSPEffectOf(NSString *key) {
    for (NSString *effect in effectSwitches()) {
        if ([key isEqualToString:effect] || [key hasPrefix:[effect stringByAppendingString:@"."]]) return effect;
    }
    return SGKeyDSP;
}

SGDSPRange SGDSPRangeFor(NSString *key) {
    for (size_t i = 0; i < sizeof kNumbers / sizeof *kNumbers; i++) {
        if ([kNumbers[i].key isEqualToString:key]) return kNumbers[i].range;
    }
    return (SGDSPRange){0, 1, 0, 0};
}

#pragma mark - reading and writing

static NSUserDefaults *store(void) {
    return NSUserDefaults.standardUserDefaults;
}

// Only the active snapshot crosses to the DSP queue. Device presets never overwrite the default EQ.
static os_unfair_lock outputEQLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary *activeOutputEQ;

static NSDictionary *outputEQSnapshot(void) {
    os_unfair_lock_lock(&outputEQLock);
    NSDictionary *snapshot = activeOutputEQ;
    os_unfair_lock_unlock(&outputEQLock);
    return snapshot;
}

static void setOutputEQSnapshot(NSDictionary *snapshot) {
    os_unfair_lock_lock(&outputEQLock);
    NSDictionary *previous = activeOutputEQ;
    activeOutputEQ = snapshot;
    os_unfair_lock_unlock(&outputEQLock);
    if (previous || snapshot) SGDSPApply(SGKeyDSPEqualizer);
}

// Manual changes are heard immediately but do not replace a saved assignment.
static BOOL editOutputEQ(NSString *key, id value) {
    if (![key isEqualToString:SGKeyDSPEqualizer] && ![key isEqualToString:SGKeyDSPEqualizerGains]) return NO;
    NSMutableDictionary *snapshot = [outputEQSnapshot() mutableCopy];
    if (!snapshot) return NO;
    snapshot[key] = value;
    setOutputEQSnapshot([snapshot copy]);
    return YES;
}

BOOL SGDSPSwitch(NSString *key) {
    if ([key isEqualToString:SGKeyDSPEqualizer]) {
        NSNumber *override = outputEQSnapshot()[key];
        if (override) return override.boolValue;
    }
    return SGHidden(key);
}

void SGDSPSetSwitch(NSString *key, BOOL on) {
    if (editOutputEQ(key, @(on))) return;
    SGSetEnabled(key, on);
    SGDSPApply(SGDSPEffectOf(key));
}

double SGDSPNumber(NSString *key) {
    SGDSPRange range = SGDSPRangeFor(key);
    id value = [store() objectForKey:key];
    if (![value isKindOfClass:NSNumber.class]) return range.fallback;
    return MAX(range.min, MIN(range.max, [value doubleValue]));
}

void SGDSPSetNumber(NSString *key, double value) {
    SGDSPRange range = SGDSPRangeFor(key);
    [store() setDouble:MAX(range.min, MIN(range.max, value)) forKey:key];
    SGDSPApply(SGDSPEffectOf(key));
}

static NSString *storedString(NSString *key) {
    id value = [store() objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : (stringDefaults()[key] ?: @"");
}

NSString *SGDSPString(NSString *key) {
    if ([key isEqualToString:SGKeyDSPEqualizerGains]) {
        return outputEQSnapshot()[key] ?: storedString(key);
    }
    return storedString(key);
}

void SGDSPSetString(NSString *key, NSString *value) {
    if (editOutputEQ(key, value ?: @"")) return;
    [store() setObject:value ?: @"" forKey:key];
    SGDSPApply(SGDSPEffectOf(key));
}

static NSUInteger gainCount(NSString *key) {
    return [key isEqualToString:SGKeyDSPCompanderGains] ? 7 : 15;
}

static double gainLimit(NSString *key) {
    return [key isEqualToString:SGKeyDSPCompanderGains] ? SGDSPCompanderGainLimit : SGDSPEqualizerGainLimit;
}

static NSArray<NSNumber *> *parseGains(NSString *key, NSString *text) {
    NSArray<NSString *> *parts = [text componentsSeparatedByString:@";"];
    NSUInteger count = gainCount(key);
    double limit = gainLimit(key);
    NSMutableArray<NSNumber *> *gains = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        double gain = i < parts.count ? parts[i].doubleValue : 0;
        [gains addObject:@(MAX(-limit, MIN(limit, gain)))];
    }
    return gains;
}

NSArray<NSNumber *> *SGDSPGains(NSString *key) {
    return parseGains(key, SGDSPString(key));
}

NSArray<NSNumber *> *SGDSPEqualizerState(BOOL *on) {
    NSDictionary *snapshot = outputEQSnapshot();
    *on = snapshot ? [snapshot[SGKeyDSPEqualizer] boolValue] : SGHidden(SGKeyDSPEqualizer);
    return parseGains(SGKeyDSPEqualizerGains, snapshot[SGKeyDSPEqualizerGains] ?: storedString(SGKeyDSPEqualizerGains));
}

static NSString *formatGains(NSString *key, NSArray<NSNumber *> *gains) {
    NSUInteger count = gainCount(key);
    double limit = gainLimit(key);
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        double gain = i < gains.count ? gains[i].doubleValue : 0;
        [parts addObject:[NSString stringWithFormat:@"%.2f", MAX(-limit, MIN(limit, gain))]];
    }
    return [parts componentsJoinedByString:@";"];
}

void SGDSPSetGains(NSString *key, NSArray<NSNumber *> *gains) {
    SGDSPSetString(key, formatGains(key, gains));
}

void SGDSPResetAll(void) {
    BOOL routed = outputEQSnapshot() != nil;
    if (routed) setOutputEQSnapshot(@{SGKeyDSPEqualizer: @NO, SGKeyDSPEqualizerGains: stringDefaults()[SGKeyDSPEqualizerGains]});
    for (size_t i = 0; i < sizeof kNumbers / sizeof *kNumbers; i++) [store() removeObjectForKey:kNumbers[i].key];
    for (NSString *key in stringDefaults()) {
        if (!routed || ![key isEqualToString:SGKeyDSPEqualizerGains]) [store() removeObjectForKey:key];
    }
    for (NSString *effect in effectSwitches()) {
        if (!routed || ![effect isEqualToString:SGKeyDSPEqualizer]) [store() removeObjectForKey:effect];
    }
    SGDSPApply(SGKeyDSP);
    for (NSString *effect in effectSwitches()) SGDSPApply(effect);
}

#pragma mark - Equalizer per output (main thread)

static NSString *outputEQUID, *outputEQName;

static NSDictionary<NSString *, NSDictionary *> *outputEQPresets(void) {
    id presets = [store() objectForKey:SGKeyDSPOutputEQPresets];
    return [presets isKindOfClass:NSDictionary.class] ? presets : @{};
}

static void outputEQChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGDSPOutputEQChangedNotification object:nil];
}

static void refreshOutputEQ(void) {
    id preset = outputEQUID.length && SGHidden(SGKeyDSPOutputEQEnabled) ? outputEQPresets()[outputEQUID] : nil;
    id gains = [preset isKindOfClass:NSDictionary.class] ? preset[@"gains"] : nil;
    setOutputEQSnapshot([gains isKindOfClass:NSString.class] ? @{SGKeyDSPEqualizer: @YES, SGKeyDSPEqualizerGains: gains} : nil);
    outputEQChanged();
}

void SGDSPOutputEQRouteChanged(NSString *uid, NSString *name) {
    // Category changes on the same route should not undo a manual EQ adjustment.
    if ([uid isEqualToString:outputEQUID] || (!uid.length && !outputEQUID.length)) return;
    outputEQUID = uid.length ? [uid copy] : nil;
    outputEQName = outputEQUID ? (name.length ? [name copy] : outputEQUID) : nil;
    refreshOutputEQ();
}

NSString *SGDSPOutputEQUID(void) { return outputEQUID; }
NSString *SGDSPOutputEQName(void) { return outputEQName; }

void SGDSPOutputEQSetEnabled(BOOL on) {
    SGSetEnabled(SGKeyDSPOutputEQEnabled, on);
    refreshOutputEQ();
}

void SGDSPOutputEQAssign(NSInteger index) {
    if (!outputEQUID.length || !SGHidden(SGKeyDSPOutputEQEnabled)) return;
    NSArray<NSString *> *names = SGDSPEqualizerPresetNames();
    if (index < -1 || index >= (NSInteger)names.count) return;
    BOOL custom = index == -1;
    NSArray<NSNumber *> *gains = custom ? SGDSPGains(SGKeyDSPEqualizerGains) : SGDSPEqualizerPreset(index);
    NSMutableDictionary *presets = [outputEQPresets() mutableCopy];
    presets[outputEQUID] = @{@"name": outputEQName, @"preset": custom ? @"Custom curve" : names[(NSUInteger)index],
                             @"gains": formatGains(SGKeyDSPEqualizerGains, gains)};
    [store() setObject:presets forKey:SGKeyDSPOutputEQPresets];
    refreshOutputEQ();
}

void SGDSPOutputEQForget(NSString *uid) {
    if (!uid.length) return;
    NSMutableDictionary *presets = [outputEQPresets() mutableCopy];
    [presets removeObjectForKey:uid];
    [store() setObject:presets forKey:SGKeyDSPOutputEQPresets];
    if ([uid isEqualToString:outputEQUID]) refreshOutputEQ();
    else outputEQChanged();
}

NSArray<NSDictionary<NSString *, NSString *> *> *SGDSPOutputEQAssignments(void) {
    NSMutableArray *list = [NSMutableArray array];
    [outputEQPresets() enumerateKeysAndObjectsUsingBlock:^(NSString *uid, id entry, BOOL *stop) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"gains"] isKindOfClass:NSString.class]) return;
        NSString *name = [uid isEqualToString:outputEQUID] ? outputEQName : entry[@"name"];
        NSString *preset = entry[@"preset"];
        if (![name isKindOfClass:NSString.class] || ![preset isKindOfClass:NSString.class]) return;
        [list addObject:@{@"uid": uid, @"name": name, @"preset": preset}];
    }];
    [list sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]]];
    return list;
}

#pragma mark - lists

NSArray<NSString *> *SGDSPConvolverModeNames(void) {
    return @[@"Original", @"Trimmed", @"Minimum phase"];
}

NSArray<NSString *> *SGDSPCrossfeedModeNames(void) {
    return @[@"Jan Meier (650 Hz, 9.5 dB)", @"Chu Moy (700 Hz, 6 dB)", @"Default (700 Hz, 4.5 dB)"];
}

NSArray<NSString *> *SGDSPReverbPresetNames(void) {
    return @[@"Ambience", @"Small room", @"Medium room", @"Large room", @"Chamber", @"Plate", @"Small hall", @"Large hall", @"Cathedral"];
}

NSArray<NSString *> *SGDSPEqualizerPresetNames(void) {
    return @[@"Flat", @"Bass", @"Loudness", @"Treble", @"Vocal", @"Warm", @"Bright", @"Rock", @"Electronic", @"Acoustic",
             @"Classical", @"Podcast"];
}

NSArray<NSNumber *> *SGDSPEqualizerPreset(NSInteger index) {
    static const double presets[][15] = {
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {6, 6, 5, 4, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {5, 5, 4, 2, 1, 0, 0, 0, 0, 0, 1, 2, 3, 4, 4},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 5},
        {-2, -2, -2, -1, -1, 0, 1, 2, 3, 3, 2, 1, 0, -1, -1},
        {2, 2, 2, 2, 1, 1, 0, 0, 0, -1, -1, -2, -2, -2, -2},
        {-1, -1, -1, 0, 0, 0, 0, 0, 1, 2, 3, 3, 3, 3, 3},
        {4, 4, 3, 1, -1, -2, -2, -1, 0, 1, 2, 3, 3, 3, 2},
        {5, 5, 4, 2, 0, -1, -2, -1, 0, 1, 1, 2, 3, 4, 4},
        {2, 2, 2, 1, 1, 0, 0, 1, 1, 2, 2, 2, 2, 1, 1},
        {3, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 3},
        {-6, -6, -4, -2, -1, 0, 1, 2, 2, 2, 1, 0, -1, -2, -3},
    };
    if (index < 0 || index >= (NSInteger)(sizeof presets / sizeof *presets)) return nil;
    NSMutableArray<NSNumber *> *gains = [NSMutableArray arrayWithCapacity:15];
    for (int i = 0; i < 15; i++) [gains addObject:@(presets[index][i])];
    return gains;
}
