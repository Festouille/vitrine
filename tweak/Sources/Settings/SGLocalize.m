#import "SGLocalize.h"
#import "Core/SGPrefs.h"

NSDictionary<NSString *, NSString *> *SGStringsFR(void);
NSDictionary<NSString *, NSString *> *SGStringsES(void);
NSDictionary<NSString *, NSString *> *SGStringsTR(void);

static SGSettingsLanguage deviceLanguage(void) {
    NSString *preferred = NSLocale.preferredLanguages.firstObject;
    if (!preferred) return SGSettingsLanguageDevice;
    NSString *code = [NSLocale componentsFromLocaleIdentifier:preferred][NSLocaleLanguageCode];
    if ([code isEqualToString:@"fr"]) return SGSettingsLanguageFrench;
    if ([code isEqualToString:@"es"]) return SGSettingsLanguageSpanish;
    if ([code isEqualToString:@"tr"]) return SGSettingsLanguageTurkish;
    return SGSettingsLanguageDevice;
}

NSString *SGL(NSString *english) {
    if (!english.length || !SGFlag(SGKeySettingsTranslate, NO)) return english;
    SGSettingsLanguage language = SGInt(SGKeySettingsLanguage, SGSettingsLanguageDevice);
    if (language == SGSettingsLanguageDevice) language = deviceLanguage();
    switch (language) {
        case SGSettingsLanguageFrench: return SGStringsFR()[english] ?: english;
        case SGSettingsLanguageSpanish: return SGStringsES()[english] ?: english;
        case SGSettingsLanguageTurkish: return SGStringsTR()[english] ?: english;
        default: return english;
    }
}
