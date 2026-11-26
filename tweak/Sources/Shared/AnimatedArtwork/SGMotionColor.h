#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

UIColor *SGMotionFrameColor(CGImageRef image, CGFloat bottomFraction);
void SGMotionBlendColor(CALayer *layer, UIColor *color, NSTimeInterval duration);

// Requests and results are on main; only one frame is decoded at a time.
@interface SGMotionColorSampler : NSObject
- (instancetype)initWithFile:(NSURL *)file bottomFraction:(CGFloat)fraction;
- (void)sampleAt:(CMTime)time looping:(BOOL)looping completion:(void (^)(UIColor *color))completion;
@end
