#import "Core/SGCore.h"
#import "Shared/StreamCounts/StreamCounts.h"

@interface SGStreamSubtitle : NSObject
@property (nonatomic, weak) UILabel *label;
@property (nonatomic, copy) NSAttributedString *original, *rendered;
@end

@implementation SGStreamSubtitle
@end

static char kSubtitleKey, kAlternateSubtitleKey, kLabelKey, kStateKey;

static void clearSubtitle(UIView *cell) {
    SGStreamSubtitle *state = objc_getAssociatedObject(cell, &kStateKey);
    if (!state) return;
    if (state.rendered && [state.label.attributedText isEqualToAttributedString:state.rendered])
        state.label.attributedText = state.original;
    objc_setAssociatedObject(cell, &kStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void updateSubtitle(UIView *cell, BOOL album) {
    UIView *subtitle = SGFindIdentifier(cell, album ? @"EncoreConsumerMobile.View.Granular.Subtitle" :
        @"Track.Row.Content.Subtitle", &kSubtitleKey);
    if (!subtitle && !album) subtitle = SGFindIdentifier(cell, @"TrackRowElement.Subtitle", &kAlternateSubtitleKey);
    UILabel *label = (UILabel *)SGFindRemembered(subtitle, &kLabelKey, ^BOOL(UIView *view) {
        return [view isKindOfClass:UILabel.class];
    });
    if (!label || !cell.window) { clearSubtitle(cell); return; }
    NSString *uri = SGStreamCountTrackURI(cell, album);
    __weak UIView *weakCell = cell;
    NSString *count = SGStreamCountText(uri, cell, ^{ [weakCell setNeedsLayout]; });
    if (!count) { clearSubtitle(cell); return; }

    SGStreamSubtitle *state = objc_getAssociatedObject(cell, &kStateKey);
    if (state.label != label) {
        clearSubtitle(cell);
        state = [SGStreamSubtitle new];
        state.label = label;
        objc_setAssociatedObject(cell, &kStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSDictionary *fallback = @{NSFontAttributeName: label.font, NSForegroundColorAttributeName: label.textColor};
    NSAttributedString *current = label.attributedText;
    if (!state.rendered || ![current isEqualToAttributedString:state.rendered])
        state.original = current ?: [[NSAttributedString alloc] initWithString:label.text ?: @"" attributes:fallback];
    NSAttributedString *original = state.original;
    NSDictionary *style = original.length ? [original attributesAtIndex:0 effectiveRange:NULL] : fallback;
    NSMutableDictionary *countStyle = [style mutableCopy];
    NSString *text = original.length ? [count stringByAppendingString:@"  ·  "] : count;
    NSMutableAttributedString *combined = [[NSMutableAttributedString alloc] initWithString:text attributes:countStyle];
    if (original) [combined appendAttributedString:original];
    state.rendered = combined;
    if (![current isEqualToAttributedString:combined]) label.attributedText = combined;
}

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    if (SGClassNamed(cell.contentView.subviews.firstObject.class, @"RetrievalListStructuredData")) updateSubtitle(cell, YES);
    else clearSubtitle(cell);
}
- (void)prepareForReuse {
    clearSubtitle((UIView *)self);
    %orig;
    [(UIView *)self setNeedsLayout];
}
%end

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (void)layoutSubviews {
    %orig;
    updateSubtitle((UIView *)self, NO);
}
- (void)prepareForReuse {
    clearSubtitle((UIView *)self);
    %orig;
    [(UIView *)self setNeedsLayout];
}
%end

%ctor {
    if (!SGNativeUI()) return;
    if (!SGHidden(SGKeyStreamCounts)) return;
    %init;
}
