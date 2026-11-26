#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Core/SGUIMode.h"
#import "Shared/HidePodcasts/HidePodcasts.h"

@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end

@interface _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer : UICollectionViewCell @end
@implementation _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer @end

@interface _TtC14Home_PillUIKit14PillScrollView : UIView @end
@implementation _TtC14Home_PillUIKit14PillScrollView @end

@interface _TtC16Home_EvoPageImpl13HomeStructure : UIView @end
@implementation _TtC16Home_EvoPageImpl13HomeStructure @end

@interface _TtC18Search_FeatureImpl22MainSERPViewController : UIViewController @end
@implementation _TtC18Search_FeatureImpl22MainSERPViewController @end

static UILabel *label(NSString *text, CGFloat size, UIFontWeight weight) {
    UILabel *view = [UILabel new];
    view.text = text;
    view.font = [UIFont systemFontOfSize:size weight:weight];
    return view;
}

static CGFloat measure(UICollectionViewCell *cell) {
    UICollectionViewLayoutAttributes *a =
        [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    a.size = cell.bounds.size;
    return [cell preferredLayoutAttributesFittingAttributes:a].size.height;
}

static void configure(UICollectionViewCell *cell, UILabel *row, NSString *identifier, BOOL home) {
    UIView *host = home ? [_TtC16Home_EvoPageImpl13HomeStructure new] : [UIView new];
    host.frame = CGRectInset(cell.bounds, 14, 0);
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    row.frame = host.bounds;
    row.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    row.accessibilityIdentifier = identifier;
    [host addSubview:row];
    [cell.contentView addSubview:host];
}

@interface SGHarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    BOOL hide = SGHidden(SGKeyHidePodcasts);
    BOOL redesigned = SGRedesignedUI();
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *page = [_TtC18Search_FeatureImpl22MainSERPViewController new];
    page.view.backgroundColor = redesigned ? UIColor.blackColor : [UIColor colorWithWhite:0.07 alpha:1];
    self.window.rootViewController = page;
    UILayoutGuide *safe = page.view.safeAreaLayoutGuide;
    UILabel *title = label(@"Hide podcasts", 38, UIFontWeightBold);
    UILabel *status = label([NSString stringWithFormat:@"%@  ·  %@", redesigned ? @"Redesigned" : @"Native",
                             hide ? @"ON" : @"OFF"], 19, UIFontWeightSemibold);
    status.textColor = hide ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, status]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    [page.view addSubview:stack];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:32],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
    ]];

    NSArray *sections = @[
        @[@"Home", @[@"Jump back into music", @"spotify:playlist:1", @NO], @[@"Episode recommendations", @"ActionCardCarouselElement", @YES]],
        @[@"Your Library", @[@"Saved albums", @"Album.Row.Library", @NO], @[@"Saved podcast", @"Podcast.Row.Library", @YES]],
        @[@"Search", @[@"Song result", @"Components.UI.TrackRowSearch", @NO],
          @[@"Audiobook result", @"Components.UI.AudiobookRowSearch", @NO],
          @[@"Podcasts", @"Components.UI.CategoryCardBrowse", @YES],
          @[@"Show result", @"Components.UI.ShowRowSearch", @YES],
          @[@"Episode result", @"Components.UI.AudioEpisodeRowSearch", @YES]],
    ];
    for (NSUInteger i = 0; i < sections.count; i++) {
        NSArray *section = sections[i];
        UIView *spacer = [UIView new];
        [spacer.heightAnchor constraintEqualToConstant:12].active = YES;
        [stack addArrangedSubview:spacer];
        [stack addArrangedSubview:label(section[0], 23, UIFontWeightBold)];
        for (NSUInteger j = 1; j < section.count; j++) {
            NSArray *item = section[j];
            BOOL filtered = hide && [item[2] boolValue];
            Class cls = i == 1 ? _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer.class :
                                _TtC12Element_List18CollectionViewCell.class;
            UICollectionViewCell *cell = [[cls alloc] initWithFrame:CGRectMake(0, 0, 340, 46)];
            cell.backgroundColor = [UIColor colorWithWhite:redesigned ? 0.14 : 0.21 alpha:1];
            cell.layer.cornerRadius = redesigned ? 17 : 8;
            UILabel *row = label(item[0], 16, UIFontWeightMedium);
            configure(cell, row, item[1], i == 0);
            [stack addArrangedSubview:cell];
            CGFloat height = measure(cell);
            [cell layoutSubviews];
            NSCAssert((height == 0) == filtered && (cell.alpha == 0) == filtered &&
                      cell.accessibilityElementsHidden == filtered && cell.userInteractionEnabled != filtered,
                      @"Unexpected filter result for %@", item[0]);
            if (filtered) {
                NSCAssert(cell.contentView.bounds.size.height > 0, @"Collapsed content must retain its natural height");
                [cell prepareForReuse];
                row.accessibilityIdentifier = @"spotify:album:replacement";
                [cell layoutSubviews];
                NSCAssert(measure(cell) > 0 && cell.alpha == 1 && !cell.accessibilityElementsHidden &&
                          cell.userInteractionEnabled, @"Reused music rows must remain visible");
                row.accessibilityIdentifier = item[1];
                [cell layoutSubviews];
                [stack removeArrangedSubview:cell];
                [cell removeFromSuperview];
            } else {
                [cell.heightAnchor constraintEqualToConstant:height].active = YES;
            }
        }
    }

    if (!redesigned) {
        UIView *pills = [_TtC14Home_PillUIKit14PillScrollView new];
        UIView *podcasts = [UIView new];
        podcasts.accessibilityIdentifier = @"home-feed-podcasts-following-chip";
        [pills addSubview:podcasts];
        [pills layoutSubviews];
        NSCAssert((podcasts.alpha == 0) == hide, @"Unexpected Home Podcasts chip visibility");
    }

    UIView *spacer = [UIView new];
    [spacer.heightAnchor constraintEqualToConstant:14].active = YES;
    [stack addArrangedSubview:spacer];
    UILabel *passed = label(@"✓  Filter and cell reuse checks passed", 15, UIFontWeightSemibold);
    passed.textColor = UIColor.systemGreenColor;
    [stack addArrangedSubview:passed];
    [self.window makeKeyAndVisible];
    NSString *result = [NSString stringWithFormat:@"%@ · %@: filter and reuse checks passed\n",
                        redesigned ? @"Redesigned" : @"Native", hide ? @"ON" : @"OFF"];
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        [result writeToFile:[documents stringByAppendingPathComponent:@"result.txt"] atomically:YES
                   encoding:NSUTF8StringEncoding error:NULL];
    });
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, nil);
    }
}
