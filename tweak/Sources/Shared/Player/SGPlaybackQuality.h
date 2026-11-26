#import "PlayerState.h"

NSString *SGPlaybackQualityText(SPTPlayerState *state);
void SGObservePlaybackQuality(UIView *owner, void (^update)(UIView *owner));
