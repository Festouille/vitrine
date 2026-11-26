// Checks the corrections remembered per output (AutoEq.m) on the Mac, through the real settings: what a route
// change to each kind of output does to the Graphic EQ, with AVAudioSession's part played by direct calls.
//
//     ./build.sh route && build/route-check
//
// Every line prints ok or FAIL; the exit status is the number of failures. The settings live in the check's
// own defaults domain, cleared before and after.
#import <Foundation/Foundation.h>
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    failures += !ok;
}

// The engine is not here.
void SGDSPApply(NSString *effect) {
}

static void clearDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
}

static NSString *const kAirPods = @"AA-BB-tacl", *const kSony = @"CC-DD-tacl", *const kSpeaker = @"Speaker";
static NSString *const kLine = @"GraphicEQ: 20 -1.0; 1000 0.0; 20000 2.0";
static NSString *const kSonyLine = @"GraphicEQ: 20 3.0; 1000 0.0; 20000 -2.0";

// What the Graphic EQ plays: the headphone's folder, or "" for nothing; "off" when its switch is off.
static NSString *playing(void) {
    if (!SGDSPSwitch(SGKeyDSPGraphicEq)) return @"off";
    return SGDSPString(SGKeyDSPGraphicEqHeadphone);
}

static NSArray<NSNumber *> *equalizer(BOOL expectedOn) {
    BOOL on;
    NSArray<NSNumber *> *gains = SGDSPEqualizerState(&on);
    return on == expectedOn ? gains : nil;
}

static void checkEqualizerRoutes(void) {
    NSString *wired = @"wired";
    NSInteger bass = 1, treble = 3;
    NSArray *bassGains = SGDSPEqualizerPreset(bass), *trebleGains = SGDSPEqualizerPreset(treble);
    SGDSPAudioOutputChanged(kAirPods, @"Bluetooth headphones");
    SGAutoEqApplyText(@"crinacle/AirPods%20Pro", kLine);
    SGAutoEqRememberOutput(YES);
    SGDSPSetSwitch(SGKeyDSP, NO);
    SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
    SGDSPSetGains(SGKeyDSPEqualizerGains, @[@2]);
    NSArray *defaultGains = equalizer(NO);
    SGDSPOutputEQAssign(bass);
    check(defaultGains && !SGDSPOutputEQAssignments().count, @"no EQ assignment while the feature is off");

    SGDSPOutputEQSetEnabled(YES);
    SGDSPOutputEQAssign(bass);
    check([equalizer(YES) isEqual:bassGains] && !SGDSPSwitch(SGKeyDSP), @"speaker applies Bass without turning Audio effects on");

    SGDSPAudioOutputChanged(kAirPods, @"Bluetooth headphones");
    check([equalizer(NO) isEqual:defaultGains] && [playing() isEqual:@"crinacle/AirPods%20Pro"],
          @"unassigned headphones use default EQ and keep their independent AutoEq correction");
    SGDSPOutputEQAssign(treble);
    check([equalizer(YES) isEqual:trebleGains] && [playing() isEqual:@"crinacle/AirPods%20Pro"],
          @"assigned Treble does not change the headphones' AutoEq correction");

    SGDSPAudioOutputChanged(wired, @"Headphones");
    SGDSPSetGains(SGKeyDSPEqualizerGains, @[@4, @(-2)]);
    defaultGains = equalizer(NO);
    SGDSPOutputEQAssign(-1);
    check([equalizer(YES) isEqual:defaultGains], @"wired headphones can save a custom curve");

    SGDSPSetGains(SGKeyDSPEqualizerGains, @[@6]);
    SGDSPAudioOutputChanged(wired, @"Headphones");
    check(equalizer(YES).firstObject.doubleValue == 6, @"a notification for the same UID does not undo a manual edit");
    SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
    check([equalizer(YES) isEqual:bassGains], @"speaker gets Bass again");
    SGDSPAudioOutputChanged(wired, @"Headphones");
    check([equalizer(YES) isEqual:defaultGains], @"reconnecting restores the saved custom curve, not an unsaved edit");

    SGDSPAudioOutputChanged(kAirPods, @"Bluetooth headphones");
    check([equalizer(YES) isEqual:trebleGains], @"Bluetooth headphones get their own preset");
    SGDSPOutputEQSetEnabled(NO);
    check([equalizer(NO) isEqual:defaultGains] && SGDSPOutputEQAssignments().count == 3,
          @"disabling restores the default and keeps all three assignments");
    SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
    check([equalizer(NO) isEqual:defaultGains], @"route changes do not apply assignments while disabled");
    SGDSPOutputEQSetEnabled(YES);
    check([equalizer(YES) isEqual:bassGains], @"enabling reapplies the current output's preset");
    SGDSPResetAll();
    check(equalizer(NO) && equalizer(NO).firstObject.doubleValue == 0, @"reset clears the active Equalizer without deleting an assignment");
    SGDSPAudioOutputChanged(nil, nil);
    NSArray *flat = SGDSPEqualizerPreset(0);
    check([equalizer(NO) isEqual:flat] && !SGDSPOutputEQUID(), @"reset also clears the default Equalizer");

    SGDSPAudioOutputChanged(kAirPods, @"Bluetooth headphones");
    SGDSPOutputEQForget(kAirPods);
    check([equalizer(NO) isEqual:flat] && SGDSPOutputEQAssignments().count == 2,
          @"removing the current assignment restores the default");

    SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
    SGDSPSaveUserPreset(@"Before presets");
    SGDSPLoadBuiltInPreset(1);
    NSArray *vocal = SGDSPEqualizerPreset(4);
    check([equalizer(YES) isEqual:bassGains], @"a full effects preset does not override the current output's EQ");
    SGDSPAudioOutputChanged(kAirPods, @"Bluetooth headphones");
    check([equalizer(YES) isEqual:vocal], @"a full effects preset survives moving to an unassigned output");
    SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
    check([equalizer(YES) isEqual:bassGains], @"a full effects preset does not overwrite the saved output assignment");
    SGDSPSaveUserPreset(@"Saved default curve");
    SGDSPLoadBuiltInPreset(0);
    SGDSPLoadUserPreset(@"Saved default curve");
    SGDSPAudioOutputChanged(kAirPods, @"Bluetooth headphones");
    check([equalizer(YES) isEqual:vocal], @"a saved full effects preset also updates the default Equalizer");
    SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
    SGDSPLoadUserPreset(@"Before presets");
    check([equalizer(YES) isEqual:bassGains], @"undoing a preset leaves the assigned EQ intact");
    SGDSPAudioOutputChanged(kAirPods, @"Bluetooth headphones");
    check([equalizer(NO) isEqual:flat], @"Before presets restores the original default EQ, not the assigned EQ");
}

int main(void) {
    @autoreleasepool {
        clearDefaults();

        // Launch on the speaker: nothing remembered, nothing changes.
        SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"off"], @"launch on the speaker: the Graphic EQ stays off");

        // AirPods connect, the user picks a correction and turns Use for AirPods on.
        SGDSPAudioOutputChanged(kAirPods, @"AirPods Pro");
        SGAutoEqApplyText(@"crinacle/AirPods%20Pro", kLine);
        check(!SGAutoEqOutputRemembered(kAirPods), @"a pick alone remembers nothing");
        SGAutoEqRememberOutput(YES);
        check(SGAutoEqOutputRemembered(kAirPods), @"Use for AirPods Pro remembers it");
        check(SGDSPSwitch(SGKeyDSP), @"the pick turned Audio effects on");

        // Back to the speaker: the AirPods' correction goes off.
        SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"off"], [NSString stringWithFormat:@"speaker: the AirPods' correction is off (%@)", playing()]);
        check([SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:@""], @"speaker: no headphone named");

        // AirPods again: their correction comes back, nodes and all, with no download.
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 20 0.0");
        SGDSPAudioOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], [NSString stringWithFormat:@"AirPods again: their correction is on (%@)", playing()]);
        check([SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:kLine], @"AirPods again: their own curve");

        // The same output again (a category change, not a new route): nothing happens.
        SGDSPSetSwitch(SGKeyDSPGraphicEq, NO);
        SGDSPAudioOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"off"], @"the same output again changes nothing");
        SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);

        // Another pair, remembered with its own correction, then the AirPods: each gets its own.
        SGDSPAudioOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"off"], @"a new pair with nothing remembered: the AirPods' correction goes off");
        SGAutoEqRememberOutput(YES);
        SGAutoEqApplyText(@"oratory1990/Sony%20WH-1000XM5", kSonyLine);
        SGDSPAudioOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"AirPods: theirs");
        SGDSPAudioOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"oratory1990/Sony%20WH-1000XM5"] && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:kSonyLine],
              @"Sony: its own pick, not the AirPods'");

        // None remembered for the Sony: a pick of None on it sticks.
        SGAutoEqTakeOff();
        SGDSPAudioOutputChanged(kAirPods, @"AirPods Pro");
        SGDSPAudioOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"off"], @"None picked for the Sony stays None for it");

        // A correction picked on the speaker, with nothing remembered there, is the user's: it stays everywhere.
        SGAutoEqForgetOutput(kSony);
        SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
        SGAutoEqApplyText(@"someone/Speaker%20Fix", kLine);
        SGDSPAudioOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"someone/Speaker%20Fix"], @"a pick made with nothing remembered is not taken off");

        // A curve of the user's own is never taken off by a route change.
        SGDSPAudioOutputChanged(kAirPods, @"AirPods Pro");
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 100 6.0");
        SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"");
        SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
        check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 100 6.0"],
              @"a hand-made curve stays on the speaker");

        // A route change never turns the effects on.
        SGDSPSetSwitch(SGKeyDSP, NO);
        SGDSPAudioOutputChanged(kAirPods, @"AirPods Pro");
        check(!SGDSPSwitch(SGKeyDSP) && [playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"AirPods with Audio effects off: correction set, effects left off");

        // Forgetting the AirPods: listed no more, and their correction stays until the next change.
        NSUInteger before = SGAutoEqRememberedOutputs().count;
        SGAutoEqRememberOutput(NO);
        check(!SGAutoEqOutputRemembered(kAirPods) && SGAutoEqRememberedOutputs().count == before - 1, @"Use for AirPods Pro off forgets them");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"forgetting leaves what plays");
        SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"once forgotten, the speaker keeps it: it is a plain pick now");

        // A renamed output keeps its pick under its new name.
        SGDSPAudioOutputChanged(kSony, @"WH-1000XM5");
        SGAutoEqRememberOutput(YES);
        SGDSPAudioOutputChanged(kSpeaker, @"Speaker");
        SGDSPAudioOutputChanged(kSony, @"Sony at work");
        check([SGAutoEqRememberedOutputs().firstObject[@"name"] isEqualToString:@"Sony at work"], @"a renamed output is listed by its new name");

        checkEqualizerRoutes();
        clearDefaults();
        printf("%d failed\n", failures);
    }
    return failures;
}
