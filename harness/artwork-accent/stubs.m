#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Home/Home.h"

NSString *SGLocalFileCoverInURL(NSString *url) { return [NSURL URLWithString:url].isFileURL ? [NSURL URLWithString:url].path : nil; }
NSURL *SGMotionCanvasIn(NSDictionary *metadata) { return nil; }

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
