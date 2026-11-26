#import "SGMotionColor.h"

UIColor *SGMotionFrameColor(CGImageRef image, CGFloat bottomFraction) {
    if (!image) return nil;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    size_t rows = MAX(1, (size_t)(height * bottomFraction));
    CGImageRef strip = CGImageCreateWithImageInRect(image, CGRectMake(0, height - rows, width, rows));
    if (!strip) return nil;
    enum { kWide = 16 };
    uint8_t pixels[kWide * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, kWide, 1, 8, kWide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    if (context) {
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        CGContextDrawImage(context, CGRectMake(0, 0, kWide, 1), strip);
        CGContextRelease(context);
    }
    CGImageRelease(strip);
    if (!context) return nil;
    CGFloat sum[3] = {0};
    for (int i = 0; i < kWide; i++) {
        for (int c = 0; c < 3; c++) sum[c] += pixels[i * 4 + c];
    }
    return [UIColor colorWithRed:sum[0] / (kWide * 255.0) green:sum[1] / (kWide * 255.0) blue:sum[2] / (kWide * 255.0) alpha:1];
}

void SGMotionBlendColor(CALayer *layer, UIColor *color, NSTimeInterval duration) {
    CGColorRef to = color.CGColor;
    CGColorRef current = layer.backgroundColor;
    if (current == to || (current && to && CGColorEqualToColor(current, to))) return;
    id from = (__bridge id)((layer.presentationLayer ?: layer).backgroundColor ?: UIColor.clearColor.CGColor);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.backgroundColor = to;
    if (duration > 0 && to) {
        CABasicAnimation *blend = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        blend.fromValue = from;
        blend.toValue = (__bridge id)to;
        blend.duration = duration;
        blend.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [layer addAnimation:blend forKey:@"motionColor"];
    } else {
        [layer removeAnimationForKey:@"motionColor"];
    }
    [CATransaction commit];
}

@implementation SGMotionColorSampler {
    AVURLAsset *_asset;
    AVAssetImageGenerator *_generator;
    CGFloat _fraction;
    BOOL _busy;
}

- (instancetype)initWithFile:(NSURL *)file bottomFraction:(CGFloat)fraction {
    if (!(self = [super init])) return nil;
    _asset = [AVURLAsset assetWithURL:file];
    _fraction = fraction;
    _generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:_asset];
    _generator.appliesPreferredTrackTransform = YES;
    _generator.maximumSize = CGSizeMake(64, 64);
    _generator.requestedTimeToleranceBefore = CMTimeMake(1, 12);
    _generator.requestedTimeToleranceAfter = CMTimeMake(1, 12);
    [_asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{}];
    return self;
}

- (void)sampleAt:(CMTime)time looping:(BOOL)looping completion:(void (^)(UIColor *))completion {
    if (_busy || !CMTIME_IS_NUMERIC(time) || CMTimeCompare(time, kCMTimeZero) < 0) return;
    if (looping) {
        if ([_asset statusOfValueForKey:@"duration" error:NULL] != AVKeyValueStatusLoaded) return;
        double duration = CMTimeGetSeconds(_asset.duration);
        if (!isfinite(duration) || duration <= 0) return;
        time = CMTimeMakeWithSeconds(fmod(CMTimeGetSeconds(time), duration), 600);
    }
    _busy = YES;
    CGFloat fraction = _fraction;
    __weak SGMotionColorSampler *weakSelf = self;
    [_generator generateCGImageAsynchronouslyForTime:time completionHandler:^(CGImageRef image, CMTime actual, NSError *error) {
        UIColor *color = SGMotionFrameColor(image, fraction);
        dispatch_async(dispatch_get_main_queue(), ^{
            SGMotionColorSampler *sampler = weakSelf;
            if (!sampler) return;
            sampler->_busy = NO;
            completion(color);
        });
    }];
}

- (void)dealloc {
    [_generator cancelAllCGImageGeneration];
}

@end
