#import "Core/SGCore.h"
#import "Shared/HidePodcasts/HidePodcasts.h"

static char kPreviousState, kNaturalSize;

static BOOL podcastComponentIn(UIView *view, SGPodcastSurface surface, BOOL categoryCard) {
    NSString *identifier = view.accessibilityIdentifier;
    if (SGPodcastComponent(identifier, surface)) return YES;
    categoryCard |= surface == SGPodcastSearch && [identifier isEqualToString:@"Components.UI.CategoryCardBrowse"];
    if (categoryCard) {
        NSString *label = view.accessibilityLabel ?: ([view isKindOfClass:UILabel.class] ? ((UILabel *)view).text : nil);
        if ([label isEqualToString:@"Podcasts"] || [label isEqualToString:@"Podcast Charts"] ||
            [label isEqualToString:@"Video Podcasts"]) return YES;
    }
    // Let the members of a mixed shelf decide for themselves, not the outer cell.
    if ([view isKindOfClass:UICollectionView.class]) return NO;
    for (UIView *child in view.subviews) {
        if (podcastComponentIn(child, surface, categoryCard)) return YES;
    }
    return NO;
}

static BOOL podcastElement(UICollectionViewCell *cell) {
    UIView *content = cell.contentView;
    if (SGClassNamed(content.subviews.firstObject.class, @"Home_EvoPageImpl13HomeStructure") ||
        SGClassNamed(cell.subviews.firstObject.class, @"Home_EvoPageImpl13HomeStructure")) {
        return podcastComponentIn(content, SGPodcastHome, NO) || podcastComponentIn(cell, SGPodcastHome, NO);
    }
    for (UIResponder *r = cell.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:UICollectionView.class] &&
            [((UIView *)r).accessibilityIdentifier isEqualToString:@"BrowsePage.ContentScrollView"]) {
            return podcastComponentIn(cell, SGPodcastSearch, NO);
        }
        if ([r isKindOfClass:UIViewController.class]) {
            if (SGClassNamed(r.class, @"Home_EvoPageImpl") || SGClassNamed(r.class, @"Home_FunkisPageImpl")) {
                return podcastComponentIn(cell, SGPodcastHome, NO);
            }
            if (SGClassNamed(r.class, @"Search_FeatureImpl")) return podcastComponentIn(cell, SGPodcastSearch, NO);
        }
    }
    return NO;
}

static void setPodcastHidden(UIView *view, BOOL hidden) {
    NSArray<NSNumber *> *state = objc_getAssociatedObject(view, &kPreviousState);
    if (hidden) {
        if (!state) objc_setAssociatedObject(view, &kPreviousState,
            @[@(view.alpha), @(view.userInteractionEnabled), @(view.accessibilityElementsHidden)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.alpha = 0;
        view.userInteractionEnabled = NO;
        view.accessibilityElementsHidden = YES;
    } else if (state) {
        view.alpha = state[0].doubleValue;
        view.userInteractionEnabled = state[1].boolValue;
        view.accessibilityElementsHidden = state[2].boolValue;
        objc_setAssociatedObject(view, &kPreviousState, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void restorePodcastSize(UICollectionViewCell *cell) {
    NSArray<NSNumber *> *size = objc_getAssociatedObject(cell, &kNaturalSize);
    if (!size) return;
    cell.contentView.autoresizingMask = size[1].unsignedIntegerValue;
    cell.contentView.frame = cell.bounds;
    objc_setAssociatedObject(cell, &kNaturalSize, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void preservePodcastSize(UICollectionViewCell *cell) {
    NSArray<NSNumber *> *size = objc_getAssociatedObject(cell, &kNaturalSize);
    if (!size) return;
    CGRect frame = cell.contentView.frame;
    frame.size.height = size[0].doubleValue;
    if (!CGRectEqualToRect(cell.contentView.frame, frame)) cell.contentView.frame = frame;
}

static UICollectionViewLayoutAttributes *withoutPodcastSize(UICollectionViewCell *cell,
                                                             UICollectionViewLayoutAttributes *attributes) {
    if (attributes.size.height <= 0) return attributes;
    UIView *content = cell.contentView;
    NSArray<NSNumber *> *size = objc_getAssociatedObject(cell, &kNaturalSize);
    objc_setAssociatedObject(cell, &kNaturalSize,
        @[@(attributes.size.height), size ? size[1] : @(content.autoresizingMask)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    preservePodcastSize(cell);
    UICollectionViewLayoutAttributes *result = [attributes copy];
    result.size = CGSizeMake(result.size.width, 0);
    return result;
}

%group SGRHidePodcasts
%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    if (objc_getAssociatedObject(cell, &kNaturalSize) && !podcastElement(cell)) restorePodcastSize(cell);
    UICollectionViewLayoutAttributes *result = %orig;
    return podcastElement(cell) ? withoutPodcastSize(cell, result) : result;
}
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    BOOL hidden = podcastElement(cell);
    if (hidden) preservePodcastSize(cell);
    else restorePodcastSize(cell);
    setPodcastHidden(cell, hidden);
}
- (void)prepareForReuse {
    restorePodcastSize((UICollectionViewCell *)self);
    setPodcastHidden((UIView *)self, NO);
    %orig;
}
%end

%hook _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    if (objc_getAssociatedObject(cell, &kNaturalSize) && !podcastComponentIn(cell, SGPodcastLibrary, NO)) restorePodcastSize(cell);
    UICollectionViewLayoutAttributes *result = %orig;
    return podcastComponentIn(cell, SGPodcastLibrary, NO) ? withoutPodcastSize(cell, result) : result;
}
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    BOOL hidden = podcastComponentIn(cell, SGPodcastLibrary, NO);
    if (hidden) preservePodcastSize(cell);
    else restorePodcastSize(cell);
    setPodcastHidden(cell, hidden);
}
- (void)prepareForReuse {
    restorePodcastSize((UICollectionViewCell *)self);
    setPodcastHidden((UIView *)self, NO);
    %orig;
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGHidden(SGKeyHidePodcasts)) return;
    %init(SGRHidePodcasts);
}
