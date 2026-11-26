#import <Foundation/Foundation.h>

#define SGKeySettingsTranslate @"spotifyglass.settingsTranslate"
#define SGKeySettingsLanguage @"spotifyglass.settingsLanguage"

typedef NS_ENUM(NSInteger, SGSettingsLanguage) {
    SGSettingsLanguageDevice,
    SGSettingsLanguageFrench,
    SGSettingsLanguageSpanish,
    SGSettingsLanguageTurkish,
};

NSString *SGL(NSString *english);
NSString *SGLUppercase(NSString *english);
