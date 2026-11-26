// Imported lyrics, on the Lyrics page beside the sources. The file picker copies in an LRC for matching
// by name, or links a file to the track playing.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "LocalFiles.h"
#import "LocalLyrics.h"

typedef NS_ENUM(NSInteger, SGLRCImportRow) {
    SGLRCImportForTrack,
    SGLRCImportByName,
    SGLRCImportOverride,
    SGLRCImportRowCount,
};

static void showAlert(UIViewController *owner, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}

// The local file playing, nil for anything else.
static NSString *playingLocalFile(void) {
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    return SGLocalFileIs(uri) ? uri : nil;
}

@interface SGImportedLRCFilesPage : SGPage <UIDocumentPickerDelegate>
@end

@implementation SGImportedLRCFilesPage {
    NSArray<NSString *> *_files;
    UIView *_footer;
    NSString *_linkTo, *_trackTitle;
    BOOL _override;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Imported lyrics";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(@"Import for current track links the file to the local file playing, whatever its tags say. "
                      "Import LRC… keeps a file for any track whose title and artist match its [ti:] and [ar:] tags, "
                      "or its name as \"Artist - Title\". Use Assign TTML or LRC… to override online lyrics for the track playing. "
                      "Swipe left to delete a file and remove its assignment.");
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _files = [SGImportedLRCFiles() arrayByAddingObjectsFromArray:SGImportedTrackLyricsFiles()];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? MAX((NSInteger)_files.count, 1)
        : (SGFlag(SGKeyTrackLyricsImport, NO) ? SGLRCImportRowCount : SGLRCImportOverride);
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == 0 ? SGSectionHeader(table, @"Files") : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? SGSectionHeaderHeight() : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) {
        UITableViewCell *cell = SGDequeueCell(table, @"import");
        if (path.row == SGLRCImportOverride) {
            SPTPlayerTrack *track = SGPlayerState().track;
            NSString *uri = SGURIString(track.URI);
            BOOL canAssign = SGCanImportTrackLyrics(uri);
            NSString *linked = SGTrackLyricsLinkedTo(uri);
            NSString *detail = linked ? [NSString stringWithFormat:@"%@ · %@", track.trackTitle ?: @"Current track", linked.lastPathComponent]
                : track.trackTitle ?: @"Start playing a song first";
            SGFillCell(cell, @"Assign TTML or LRC…", canAssign ? detail : @"Start playing a song first",
                       canAssign ? nil : SGGrey(), @"music.note");
        } else if (path.row == SGLRCImportByName) {
            SGFillCell(cell, @"Import LRC…", @"Matched by title and artist", nil, @"square.and.arrow.down");
        } else {
            NSString *uri = playingLocalFile();
            NSString *title = SGLocalFileInfo(uri)[@"title"] ?: @"The local file playing";
            SGFillCell(cell, @"Import for current track…", uri ? title : @"Start playing a local track first",
                       uri ? nil : SGGrey(), @"music.note");
        }
        BOOL enabled = [self tableView:table shouldHighlightRowAtIndexPath:path];
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
        return cell;
    }
    UITableViewCell *cell = SGDequeueCell(table, @"file");
    if (!_files.count) {
        SGFillCell(cell, @"No imported files", nil, SGGrey(), nil);
        return cell;
    }
    NSString *name = _files[(NSUInteger)path.row];
    if (name.pathComponents.count > 1) {
        SGFillCell(cell, name.lastPathComponent, @"Track import", nil, nil);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSInteger offset = SGImportedLRCOffset(name);
    NSString *detail = offset ? [NSString stringWithFormat:@"Timing offset: %+ld ms", (long)offset] : @"Timing offset: 0 ms";
    SGFillCell(cell, name, detail, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) return _files.count && _files[(NSUInteger)path.row].pathComponents.count == 1;
    if (path.row == SGLRCImportOverride) return SGCanImportTrackLyrics(SGURIString(SGPlayerState().track.URI));
    return path.row == SGLRCImportByName || playingLocalFile();
}

- (void)editOffsetFor:(NSString *)name {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LRC Timing Offset"
        message:@"Enter milliseconds. Use a negative value for earlier lyrics, a positive value for later lyrics, or 0 to reset. This affects timed lines only."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.text = [NSString stringWithFormat:@"%ld", (long)SGImportedLRCOffset(name)];
        field.accessibilityLabel = @"Timing offset in milliseconds";
    }];
    UITextField *field = alert.textFields.firstObject;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSScanner *scanner = [NSScanner scannerWithString:field.text ?: @""];
        NSInteger offset;
        if (![scanner scanInteger:&offset] || !scanner.isAtEnd || offset < -SGImportedLRCOffsetLimit || offset > SGImportedLRCOffsetLimit) {
            dispatch_async(dispatch_get_main_queue(), ^{
                showAlert(self, @"Invalid timing offset", @"Enter a whole number between −60000 and 60000 milliseconds.");
            });
            return;
        }
        SGSetImportedLRCOffset(name, offset);
        [self reloadFiles];
    }]];
    SGPresentDark(alert);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) {
        if ([self tableView:table shouldHighlightRowAtIndexPath:path]) [self editOffsetFor:_files[(NSUInteger)path.row]];
        return;
    }
    if (![self tableView:table shouldHighlightRowAtIndexPath:path]) return;
    _override = path.row == SGLRCImportOverride;
    SPTPlayerTrack *track = SGPlayerState().track;
    _trackTitle = _override ? track.trackTitle : nil;
    _linkTo = _override ? SGURIString(track.URI) : path.row == SGLRCImportForTrack ? playingLocalFile() : nil;
    // .lrc is nobody's registered type, so Files offers any file and the name is checked after.
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 0 || !_files.count) return nil;
    NSString *name = _files[(NSUInteger)path.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            BOOL deleted = SGDeleteImportedLRC(name);
            if (deleted) [self reloadFiles];
            else showAlert(self, @"Could not delete the file", nil);
            done(deleted);
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

- (void)reloadFiles {
    _files = [SGImportedLRCFiles() arrayByAddingObjectsFromArray:SGImportedTrackLyricsFiles()];
    [self.tableView reloadData];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    if (!_override && ![url.pathExtension.lowercaseString isEqualToString:@"lrc"]) {
        showAlert(self, @"Not an LRC file", @"Pick a file whose name ends in .lrc.");
        return;
    }
    NSError *error = nil;
    NSString *name = _override ? SGImportTrackLyrics(url, _linkTo, &error) : SGImportLRC(url, _linkTo, &error);
    if (!name) {
        showAlert(self, @"Could not import the file", error.localizedDescription);
        return;
    }
    [self reloadFiles];
    if (_linkTo) {
        NSString *title = _override ? _trackTitle : SGLocalFileInfo(_linkTo)[@"title"];
        showAlert(self, @"Lyrics linked", [NSString stringWithFormat:@"%@ now gives the lyrics for %@.", name.lastPathComponent,
                                                                     title ? [NSString stringWithFormat:@"\"%@\"", title] : @"this track"]);
    }
}

@end

UIViewController *SGImportedLRCPage(void) {
    return [SGImportedLRCFilesPage new];
}
