#import "SaveCanvas.h"
#import "AnimatedArtwork.h"
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"

static void shareCanvas(NSURL *url) {
    SGMotionFileForExport(url, ^(NSURL *file) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *top = SGTopController();
            if (!top.viewIfLoaded.window) return;
            if (!file.isFileURL) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Could Not Save Canvas"
                                                                               message:@"The Canvas couldn’t be downloaded. Try again later."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                SGPresentDark(alert);
                [top presentViewController:alert animated:YES completion:nil];
                return;
            }
            UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
            sheet.popoverPresentationController.sourceView = top.view;
            CGRect bounds = top.view.bounds;
            sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds), 1, 1);
            SGPresentDark(sheet);
            [top presentViewController:sheet animated:YES completion:nil];
        });
    });
}

static BOOL isCurrentTrack(NSString *uri) {
    return SGFlag(SGKeySaveCanvas, NO) && [uri isEqualToString:SGURIString(SGPlayerState().track.URI)];
}

static UIAction *saveAction(NSString *uri, NSURL *url) {
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length) return nil;
    return [UIAction actionWithTitle:@"Save Canvas" image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                          identifier:nil handler:^(UIAction *action) {
        if (isCurrentTrack(uri)) shareCanvas(url);
    }];
}

void SGResolveSaveCanvasAction(void (^done)(UIAction *action)) {
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *uri = SGURIString(track.URI);
    if (!SGFlag(SGKeySaveCanvas, NO) || ![uri hasPrefix:@"spotify:track:"]) {
        done(nil);
        return;
    }
    SGMotionResolveCanvas(uri, SGMotionCanvasIn(track.metadata), ^(NSURL *canvas) {
        done(isCurrentTrack(uri) ? saveAction(uri, canvas) : nil);
    });
}

UIMenuElement *SGSaveCanvasMenuElement(void) {
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *uri = SGURIString(track.URI);
    if (!SGFlag(SGKeySaveCanvas, NO) || ![uri hasPrefix:@"spotify:track:"]) return nil;
    NSURL *canvas = SGMotionCanvasIn(track.metadata);
    if (canvas) return saveAction(uri, canvas);
    return [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        if (!isCurrentTrack(uri)) {
            completion(@[]);
            return;
        }
        SGResolveSaveCanvasAction(^(UIAction *action) { completion(action ? @[action] : @[]); });
    }];
}
