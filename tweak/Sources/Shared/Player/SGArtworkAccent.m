#import "SGArtworkAccent.h"
#import "PlayerState.h"
#import "SGLastTrack.h"

NSInteger SGArtworkAccentRGB(UIImage *image) {
    if (!image.CGImage) return -1;
    enum { side = 32, bins = 24 };
    uint8_t pixels[side * side * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return -1;
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), image.CGImage);
    CGContextRelease(context);

    double weights[bins] = {0}, hues[bins] = {0}, saturations[bins] = {0};
    for (NSUInteger i = 0; i < sizeof(pixels); i += 4) {
        if (pixels[i + 3] < 128) continue;
        double r = pixels[i] / (double)pixels[i + 3], g = pixels[i + 1] / (double)pixels[i + 3],
               b = pixels[i + 2] / (double)pixels[i + 3];
        double high = MAX(r, MAX(g, b)), range = high - MIN(r, MIN(g, b));
        if (high < 0.10 || range < 0.07) continue;
        double saturation = range / high;
        if (saturation < 0.18) continue;
        double hue = high == r ? (g - b) / range : high == g ? 2 + (b - r) / range : 4 + (r - g) / range;
        double bucket = hue * bins / 6.0;
        NSInteger rounded = (NSInteger)lround(bucket);
        NSUInteger bin = (rounded + bins) % bins;
        double weight = range * saturation;
        weights[bin] += weight;
        hues[bin] += (bucket - rounded) * weight;
        saturations[bin] += saturation * weight;
    }
    NSUInteger best = 0;
    for (NSUInteger i = 1; i < bins; i++) if (weights[i] > weights[best]) best = i;
    if (weights[best] < 1) return -1;
    double hue = fmod(1 + (best + hues[best] / weights[best]) / bins, 1);
    double saturation = MIN(0.78, MAX(0.42, saturations[best] / weights[best]));
    CGFloat r, g, b, alpha;
    [[UIColor colorWithHue:hue saturation:saturation brightness:0.96 alpha:1] getRed:&r green:&g blue:&b alpha:&alpha];
    return (lround(r * 255) << 16) | (lround(g * 255) << 8) | lround(b * 255);
}

@interface SGArtworkAccentObserver : NSObject <SGPlayerStateObserver>
@property (nonatomic, copy) void (^changed)(NSInteger rgb);
@end

@implementation SGArtworkAccentObserver {
    SPTPlayerTrack *_track;
    NSURL *_url;
    NSUInteger _request;
    NSInteger _rgb;
}

- (instancetype)init {
    if ((self = [super init])) _rgb = -1;
    return self;
}

- (void)applyRGB:(NSInteger)rgb {
    if (_rgb == rgb) return;
    _rgb = rgb;
    self.changed(rgb);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self playerStateDidReport:state];
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (_track == state.track) return;
    _track = state.track;
    SGShownTrack *track = SGShownTrackNow();
    NSURL *url = track.current ? track.artworkURL : nil;
    if (_url == url || [_url isEqual:url]) return;
    _url = url;
    NSUInteger request = ++_request;
    if (!url) {
        [self applyRGB:-1];
        return;
    }
    SGShownTrackArtwork(track, ^(UIImage *image) {
        if (self->_request != request) return;
        if (!image) {
            [self applyRGB:-1];
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSInteger rgb = SGArtworkAccentRGB(image);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_request == request) [self applyRGB:rgb];
            });
        });
    });
}

@end

void SGObserveArtworkAccent(void (^changed)(NSInteger rgb)) {
    static SGArtworkAccentObserver *observer;
    observer = [SGArtworkAccentObserver new];
    observer.changed = changed;
    SGAddPlayerStateObserver(observer);
    [observer playerStateDidReport:SGPlayerState()];
}
