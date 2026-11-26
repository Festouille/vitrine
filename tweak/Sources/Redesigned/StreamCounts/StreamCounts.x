#import "Core/SGCore.h"
#import "Shared/StreamCounts/StreamCounts.h"
#import "Redesigned/Kit/SGRTokens.h"

@interface SGRStreamSubtitle : NSObject
@property (nonatomic, weak) UILabel *label;
@property (nonatomic, copy) NSAttributedString *original, *rendered;
@property (nonatomic, strong) UILabel *countLabel;
@end

@implementation SGRStreamSubtitle
@end

static char kSubtitleKey, kAlternateSubtitleKey, kLabelKey, kStateKey;

static void clearSubtitle(UIView *cell) {
    SGRStreamSubtitle *state = objc_getAssociatedObject(cell, &kStateKey);
    if (!state) return;
    if (state.rendered && [state.label.attributedText isEqualToAttributedString:state.rendered])
        state.label.attributedText = state.original;
    [state.countLabel removeFromSuperview];
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

    SGRStreamSubtitle *state = objc_getAssociatedObject(cell, &kStateKey);
    if (state.label != label) {
        clearSubtitle(cell);
        state = [SGRStreamSubtitle new];
        state.label = label;
        objc_setAssociatedObject(cell, &kStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (subtitle.alpha == 0) {
        if (state.rendered && [label.attributedText isEqualToAttributedString:state.rendered])
            label.attributedText = state.original;
        UILabel *number = state.countLabel;
        if (!number) {
            state.countLabel = number = [UILabel new];
            number.textAlignment = NSTextAlignmentNatural;
            number.userInteractionEnabled = NO;
            [cell addSubview:number];
        }
        number.text = count;
        number.font = SGRMonospacedDigitsFont(label.font);
        number.textColor = SGRSecondary();
        number.accessibilityLabel = [NSString localizedStringWithFormat:NSLocalizedString(@"%@ streams", nil), count];
        CGRect subtitleFrame = [label convertRect:label.bounds toView:cell];
        CGFloat width = ceil([number sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width);
        CGFloat y = CGRectGetMaxY(cell.bounds) - label.font.lineHeight - 4;
        CGFloat x = label.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ?
            CGRectGetMinX(subtitleFrame) : CGRectGetMaxX(subtitleFrame) - width;
        number.frame = CGRectMake(x, y, width, label.font.lineHeight);
        return;
    }
    [state.countLabel removeFromSuperview];
    state.countLabel = nil;
    NSDictionary *fallback = @{NSFontAttributeName: label.font, NSForegroundColorAttributeName: label.textColor};
    NSAttributedString *current = label.attributedText;
    if (!state.rendered || ![current isEqualToAttributedString:state.rendered])
        state.original = current ?: [[NSAttributedString alloc] initWithString:label.text ?: @"" attributes:fallback];
    NSAttributedString *original = state.original;
    NSDictionary *style = original.length ? [original attributesAtIndex:0 effectiveRange:NULL] : fallback;
    NSMutableDictionary *countStyle = [style mutableCopy];
    countStyle[NSFontAttributeName] = SGRMonospacedDigitsFont(label.font);
    countStyle[NSForegroundColorAttributeName] = SGRSecondary();
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
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGHidden(SGKeyStreamCounts)) return;
    %init;
}
