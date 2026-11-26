#import <UIKit/UIKit.h>
#import "Core/SGGlass.h"

static inline void SGLyricsAfterLineMenu(UIViewController *presenter, dispatch_block_t action) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id<UIViewControllerTransitionCoordinator> transition = presenter.presentedViewController.transitionCoordinator;
        if (![transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            action();
        }]) action();
    });
}

static inline void SGLyricsShowLineActions(NSString *text, UIView *anchor, void (^explain)(void)) {
    if (!text.length || !anchor.window) return;
    UIResponder *owner = anchor;
    while (owner && ![owner isKindOfClass:UIViewController.class]) owner = owner.nextResponder;
    UIViewController *presenter = (UIViewController *)owner;
    if (!presenter || presenter.presentedViewController) return;
    CGRect rect = [anchor convertRect:anchor.bounds toView:presenter.view];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    menu.popoverPresentationController.sourceView = presenter.view;
    menu.popoverPresentationController.sourceRect = rect;
    [menu addAction:[UIAlertAction actionWithTitle:@"Copy Line" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = text;
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Share Line…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        SGLyricsAfterLineMenu(presenter, ^{
            if (!presenter.view.window || presenter.presentedViewController) return;
            UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
            sheet.popoverPresentationController.sourceView = presenter.view;
            sheet.popoverPresentationController.sourceRect = rect;
            SGPresentDark(sheet);
            [presenter presentViewController:sheet animated:YES completion:nil];
        });
    }]];
    if (explain) [menu addAction:[UIAlertAction actionWithTitle:@"Explain Line" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        SGLyricsAfterLineMenu(presenter, explain);
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(menu);
    [presenter presentViewController:menu animated:YES completion:nil];
}
