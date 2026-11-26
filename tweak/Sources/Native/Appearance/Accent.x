// Accent color: Spotify's green, #1ED760, is one token. Its three components occur once in the
// whole binary, and every green the app draws, from the play button to the "Zobrazit vše" links
// and the progress bar, is that token or a state blended from it. So it is swapped where it is
// born, in the UIColor initializer, and the blends follow. Lottie animations carry their own green
// and are caught at the layer, below. Image assets with green baked in, the logo above all, are
// out of reach.
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Shared/Player/SGArtworkAccent.h"
#import "Native/Home/Home.h"
#import "Appearance.h"

// The greens the app is known to build from literals: the token, and the older brand green the
// upsell backend still names.
static const uint32_t kGreens[] = {0x1ED760, 0x1DB954};

static _Atomic NSInteger sg_accent = -1;
static NSInteger sg_baseAccent = -1;
static NSInteger sg_artworkAccent = -1;

NSInteger SGArtworkAccentColorRGB(void) {
    return sg_artworkAccent;
}

static NSInteger chosen(void) {
    NSInteger rgb = SGInt(SGKeyAccent, -1);
    return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : -1;
}

static void unpack(uint32_t rgb, CGFloat *r, CGFloat *g, CGFloat *b) {
    *r = ((rgb >> 16) & 0xFF) / 255.0;
    *g = ((rgb >> 8) & 0xFF) / 255.0;
    *b = (rgb & 0xFF) / 255.0;
}

UIColor *SGAccentColor(void) {
    NSInteger rgb = sg_artworkAccent >= 0 ? sg_artworkAccent : chosen();
    if (rgb < 0) return nil;
    CGFloat r, g, b;
    unpack((uint32_t)rgb, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

NSInteger SGAccentRGB(void) {
    NSInteger rgb = chosen();
    return rgb < 0 ? SGSpotifyGreen : rgb;
}

// A darker green than the token comes out as the accent darkened by the same amount, so the two
// keep their relation.
static BOOL swap(CGFloat *r, CGFloat *g, CGFloat *b) {
    NSInteger rgb = atomic_load_explicit(&sg_accent, memory_order_relaxed);
    if (rgb < 0) return NO;
    for (size_t i = 0; i < sizeof(kGreens) / sizeof(kGreens[0]); i++) {
        CGFloat gr, gg, gb;
        unpack(kGreens[i], &gr, &gg, &gb);
        if (fabs(*r - gr) > 0.01 || fabs(*g - gg) > 0.01 || fabs(*b - gb) > 0.01) continue;
        CGFloat ar, ag, ab;
        unpack((uint32_t)rgb, &ar, &ag, &ab);
        CGFloat factor = MAX(gr, MAX(gg, gb)) / (0xD7 / 255.0);
        *r = MIN(1, ar * factor);
        *g = MIN(1, ag * factor);
        *b = MIN(1, ab * factor);
        return YES;
    }
    return NO;
}

%hook UIColor
- (UIColor *)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
%end

// Lottie draws its animations, the play indicator and the checkmarks among them, from colors
// in the animation file straight onto shape layers, or into color keyframes, never through
// UIColor. The same swap goes on the CGColor. Layers get set off the main thread too, so the
// copy is made with CoreGraphics alone; NULL when the color is not one of the greens.
static CGColorRef swappedCopy(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetNumberOfComponents(color) != 4) return NULL;
    const CGFloat *c = CGColorGetComponents(color);
    CGFloat r = c[0], g = c[1], b = c[2];
    if (!swap(&r, &g, &b)) return NULL;
    CGFloat out[] = {r, g, b, c[3]};
    return CGColorCreate(CGColorGetColorSpace(color), out);
}

static id swappedValue(id value) {
    CGColorRef swapped = swappedCopy((__bridge CGColorRef)value);
    if (!swapped) return value;
    id boxed = (__bridge_transfer id)swapped;
    return boxed;
}

%hook CAShapeLayer
- (void)setFillColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
- (void)setStrokeColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CABasicAnimation
- (void)setFromValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
- (void)setToValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
%end

%hook CAKeyframeAnimation
- (void)setValues:(NSArray *)values {
    NSMutableArray *mapped = nil;
    for (NSUInteger i = 0; i < values.count; i++) {
        id swapped = swappedValue(values[i]);
        if (swapped == values[i] && !mapped) continue;
        if (!mapped) mapped = [values mutableCopy];
        mapped[i] = swapped;
    }
    NSArray *used = mapped ?: values;
    %orig(used);
}
%end

static UIColor *repaintColor(UIColor *color, NSInteger before, NSInteger after) {
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return nil;
    for (size_t i = 0; i < sizeof(kGreens) / sizeof(kGreens[0]); i++) {
        CGFloat gr, gg, gb, pr, pg, pb;
        unpack(kGreens[i], &gr, &gg, &gb);
        CGFloat factor = gg / (0xD7 / 255.0);
        unpack(before < 0 ? kGreens[i] : (uint32_t)before, &pr, &pg, &pb);
        CGFloat scale = before < 0 ? 1 : factor;
        if (fabs(r - pr * scale) > 0.004 || fabs(g - pg * scale) > 0.004 || fabs(b - pb * scale) > 0.004) continue;
        if (after < 0) return [UIColor colorWithRed:gr green:gg blue:gb alpha:a];
        unpack((uint32_t)after, &r, &g, &b);
        return [UIColor colorWithRed:r * factor green:g * factor blue:b * factor alpha:a];
    }
    return nil;
}

static void repaintLayer(CALayer *layer, NSInteger before, NSInteger after) {
    UIColor *background = layer.backgroundColor ? repaintColor([UIColor colorWithCGColor:layer.backgroundColor], before, after) : nil;
    if (background) layer.backgroundColor = background.CGColor;
    if ([layer isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *shape = (CAShapeLayer *)layer;
        UIColor *fill = shape.fillColor ? repaintColor([UIColor colorWithCGColor:shape.fillColor], before, after) : nil;
        UIColor *stroke = shape.strokeColor ? repaintColor([UIColor colorWithCGColor:shape.strokeColor], before, after) : nil;
        if (fill) shape.fillColor = fill.CGColor;
        if (stroke) shape.strokeColor = stroke.CGColor;
    }
    for (CALayer *child in layer.sublayers) repaintLayer(child, before, after);
}

static void repaintViews(UIWindow *window, NSInteger before, NSInteger after) {
    SGForEachView(window, ^(UIView *view) {
        UIColor *tint = repaintColor(view.tintColor, before, after);
        if (tint) view.tintColor = tint;
        if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            UIColor *text = repaintColor(label.textColor, before, after);
            if (text) label.textColor = text;
        } else if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            UIButtonConfiguration *config = button.configuration;
            UIColor *foreground = repaintColor(config.baseForegroundColor, before, after);
            UIColor *background = repaintColor(config.baseBackgroundColor, before, after);
            if (foreground || background) {
                if (foreground) config.baseForegroundColor = foreground;
                if (background) config.baseBackgroundColor = background;
                button.configuration = config;
            }
        }
    });
    repaintLayer(window.layer, before, after);
}

static void updateArtworkAccent(NSInteger rgb) {
    NSInteger before = atomic_load_explicit(&sg_accent, memory_order_relaxed);
    NSInteger after = rgb < 0 ? sg_baseAccent : rgb;
    sg_artworkAccent = rgb;
    atomic_store_explicit(&sg_accent, after, memory_order_relaxed);
    if (before != after) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) repaintViews(window, before, after);
        }
        [CATransaction commit];
    }
    SGHomeArtworkAccentChanged();
}

%ctor {
    if (!SGNativeUI()) return;
    BOOL artwork = SGHidden(SGKeyArtworkAccent);
    sg_baseAccent = chosen();
    atomic_store_explicit(&sg_accent, sg_baseAccent, memory_order_relaxed);
    if (sg_baseAccent >= 0 || artwork) %init;
    if (artwork) dispatch_async(dispatch_get_main_queue(), ^{ SGObserveArtworkAccent(^(NSInteger rgb) { updateArtworkAccent(rgb); }); });
}
