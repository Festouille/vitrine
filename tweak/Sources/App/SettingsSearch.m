#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGLocalize.h"
#import "Settings/SGPageStyle.h"
#import "SettingsSearch.h"

@interface SGSettingsMatch : NSObject
@property (nonatomic, strong) SGModRow *row;
@property (nonatomic, copy) NSArray<SGModPage *> *route;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *englishText;
@end

@implementation SGSettingsMatch
@end

static void indexPage(NSArray<SGModPage *> *route, NSString *path, NSString *englishPath, NSMutableArray<SGSettingsMatch *> *index) {
    [route.lastObject enumerateVisibleRows:^(SGModRow *row, NSString *section) {
        NSString *location = section.length ? [NSString stringWithFormat:@"%@ › %@", path, SGL(section)] : path;
        if (row.key || row.page || row.action || row.number || row.menu || row.segments.count) {
            SGSettingsMatch *match = [SGSettingsMatch new];
            match.row = row;
            match.route = route;
            match.path = location;
            NSString *englishLocation = section.length ? [NSString stringWithFormat:@"%@ › %@", englishPath, section] : englishPath;
            match.text = [NSString stringWithFormat:@"%@ %@ %@ %@",
                          SGL(row.title), SGL(row.subtitle) ?: @"", SGL(row.info) ?: @"", location];
            match.englishText = [NSString stringWithFormat:@"%@ %@ %@ %@",
                                 row.title, row.subtitle ?: @"", row.info ?: @"", englishLocation];
            [index addObject:match];
        }
        if (!row.searchChildren || !row.page || [route.lastObject isWaiting:row] || route.count >= 6) return;
        UIViewController *child = row.page();
        if ([child isKindOfClass:SGModPage.class]) {
            indexPage([route arrayByAddingObject:(SGModPage *)child],
                      [NSString stringWithFormat:@"%@ › %@", path, SGL(row.title)],
                      [NSString stringWithFormat:@"%@ › %@", englishPath, row.title], index);
        }
    }];
}

static BOOL containsTerms(NSString *text, NSArray<NSString *> *terms) {
    for (NSString *term in terms) {
        if (term.length && [text rangeOfString:term options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) return NO;
    }
    return YES;
}

@interface SGSettingsSearch : SGPage <UISearchBarDelegate>
@property (nonatomic, weak) SGModPage *root;
@end

@implementation SGSettingsSearch {
    UISearchBar *_bar;
    NSArray<SGSettingsMatch *> *_index;
    NSArray<SGSettingsMatch *> *_results;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Search Mod Settings";
    _bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 56)];
    _bar.searchBarStyle = UISearchBarStyleMinimal;
    _bar.placeholder = SGL(@"Search settings");
    _bar.delegate = self;
    self.tableView.tableHeaderView = _bar;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self searchBar:_bar textDidChange:@""];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_bar becomeFirstResponder];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    SGModPage *root = self.root;
    if (!root) return;
    NSArray<NSString *> *terms = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL hasQuery = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    if (hasQuery && !_index) {
        NSMutableArray<SGSettingsMatch *> *index = [NSMutableArray array];
        indexPage(@[root], SGL(@"Mod Settings"), @"Mod Settings", index);
        _index = index;
    }
    NSMutableArray *results = [NSMutableArray array];
    if (hasQuery) for (SGSettingsMatch *match in _index) {
        if (containsTerms(match.text, terms) || containsTerms(match.englishText, terms)) [results addObject:match];
    }
    _results = results;
    self.tableView.tableFooterView = results.count ? nil : SGNote(hasQuery ? @"No settings found." : @"Search by setting name or page.");
    [self.tableView reloadData];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UIView *note = self.tableView.tableFooterView;
    if (note) SGFitNote(self.tableView, note, 16, 16);
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_results.count;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGSettingsMatch *match = _results[(NSUInteger)path.row];
    UITableViewCell *cell = SGDequeueCell(table, @"result");
    SGFillCell(cell, match.row.title, match.path, nil, nil);
    cell.accessoryView = SGChevronView();
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    SGSettingsMatch *match = _results[(NSUInteger)path.row];
    UINavigationController *nav = self.navigationController;
    SGModPage *root = self.root;
    if (!nav || !root) return;
    NSUInteger rootIndex = [nav.viewControllers indexOfObjectIdenticalTo:root];
    if (rootIndex == NSNotFound) return;
    [_bar resignFirstResponder];
    [match.route.lastObject revealRowOnAppearance:match.row];
    if (match.route.count == 1) {
        [nav popToViewController:root animated:YES];
        return;
    }
    NSArray *prefix = [nav.viewControllers subarrayWithRange:NSMakeRange(0, rootIndex)];
    [nav setViewControllers:[prefix arrayByAddingObjectsFromArray:match.route] animated:YES];
}

@end

SGModRow *SGSettingsSearchRow(SGModPage *(^root)(void)) {
    SGModRow *row = SGPageRow(@"Search Mod Settings", ^UIViewController *{
        SGSettingsSearch *search = [[SGSettingsSearch alloc] initWithStyle:UITableViewStyleInsetGrouped];
        search.root = root();
        return search;
    });
    row.searchChildren = NO;
    return SGWithTile(row, @"magnifyingglass", UIColor.systemGrayColor);
}
