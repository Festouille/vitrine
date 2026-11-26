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

static SGSettingsLanguage settingsLanguage(void) {
    if (!SGFlag(SGKeySettingsTranslate, NO)) return SGSettingsLanguageDevice;
    SGSettingsLanguage language = SGInt(SGKeySettingsLanguage, SGSettingsLanguageDevice);
    return language == SGSettingsLanguageDevice ? deviceLanguage() : language;
}

static NSString *translate(NSString *english, SGSettingsLanguage language) {
    if (!english.length) return english;
    switch (language) {
        case SGSettingsLanguageFrench: return SGStringsFR()[english] ?: english;
        case SGSettingsLanguageSpanish: return SGStringsES()[english] ?: english;
        case SGSettingsLanguageTurkish: return SGStringsTR()[english] ?: english;
        default: return english;
    }
}

NSString *SGL(NSString *english) {
    return english.length ? translate(english, settingsLanguage()) : english;
}

NSString *SGLUppercase(NSString *english) {
    SGSettingsLanguage language = settingsLanguage();
    NSString *text = translate(english, language);
    if (language == SGSettingsLanguageTurkish) {
        return [text uppercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"tr"]];
    }
    return text.uppercaseString;
}
