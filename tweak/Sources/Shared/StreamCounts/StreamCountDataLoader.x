#import "Core/SGCore.h"
#import "Shared/StreamCounts/StreamCounts.h"

%hook SPTDataLoaderService
- (id)createDataLoaderFactoryWithAuthorisers:(NSArray *)authorisers {
    id factory = %orig;
    if (authorisers.count) SGStreamCountRememberDataLoader(factory);
    return factory;
}
%end

%ctor {
    if (!SGHidden(SGKeyStreamCounts)) return;
    %init;
}
