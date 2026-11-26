#import <UIKit/UIKit.h>

#define SGKeySaveCanvas @"spotifyglass.player.saveCanvas"

void SGResolveSaveCanvasAction(void (^done)(UIAction *action));
UIMenuElement *SGSaveCanvasMenuElement(void);
