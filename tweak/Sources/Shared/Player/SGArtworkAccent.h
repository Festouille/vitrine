#import <UIKit/UIKit.h>

NSInteger SGArtworkAccentRGB(UIImage *image); // -1 if the artwork has no usable color
void SGObserveArtworkAccent(void (^changed)(NSInteger rgb)); // delivers changes on main
