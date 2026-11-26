#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRDownload.h"
#import "Redesigned/Home/Home.h"

NSURL *SGMotionCanvasIn(NSDictionary *metadata) { return nil; }
void SGNowPlayingSetExtras(NSString *owner, NSDictionary *extras, NSString *title) {}
__weak UIView *sgr_nowPlayingRoot;
BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view)) { return NO; }
BOOL SGUseLegacyGlass(void) { return NO; }
void SGAlbumQueueMarkSource(UIView *view) {}
BOOL SGRReadDownload(UIView *source, SGRDownloadState *state, CGFloat *progress) { return NO; }
BOOL SGRReadAddTo(UIView *source, BOOL *added) { return NO; }
@implementation SGRDownloadGlyph
- (void)showState:(SGRDownloadState)state progress:(CGFloat)progress animated:(BOOL)animated {}
@end
const CGFloat SGRBarDim = 0;
UIView *SGRGlassInside(UIView *control, const void *key, CGFloat side) { return nil; }
UIView *SGRDarkenGlass(UIView *pane, const void *key, CGFloat radius, CGFloat alpha) { return nil; }
void SGRConceal(UIView *view) {}

BOOL SGRHomeLook(void) { return YES; }
CFTimeInterval SGRHomeProbeBegin(void) { return 0; }
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began) {}
UIControl *SGRHomeTopPicksShowAll(NSString **title) { return nil; }
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *key) { return nil; }
BOOL SGRIsAvatar(UIView *view) { return NO; }
void SGRActivate(UIView *source) {}
void SGRFollowOffset(UIScrollView *scroll, const void *key, void (^follow)(UIScrollView *scroll)) {}
void SGRHardTopEdge(UIScrollView *scroll) {}
void SGRHoldClear(UIView *view) {}
void SGRHoldClearClass(Class cls) {}
void SGRShowGlass(UIView *shape, BOOL shown) {}
UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent) { return nil; }
