#import "LSNocilla.h"
#import "LSNSURLHook.h"
#import "LSStubRequest.h"
#import "LSHTTPRequestDSLRepresentation.h"
#import "LSASIHTTPRequestHook.h"
#import "LSNSURLSessionHook.h"
#import "LSASIHTTPRequestHook.h"

NSString * const LSUnexpectedRequest = @"Unexpected Request";

@interface LSNocilla ()
@property (nonatomic, strong) NSMutableArray *mutableRequests;
@property (nonatomic, strong) NSMutableArray *hooks;
@property (nonatomic, assign, getter = isStarted) BOOL started;
@property (nonatomic, strong) dispatch_queue_t stubsQueue;
@property (nonatomic, assign) BOOL stubbingAllowed;
@property (nonatomic, strong) NSString *stubbingDisallowedMessage;

- (void)loadHooks;
- (void)unloadHooks;
@end

static LSNocilla *sharedInstace = nil;

@implementation LSNocilla

+ (LSNocilla *)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstace = [[self alloc] init];
    });
    return sharedInstace;
}

- (id)init {
    self = [super init];
    if (self) {
        _stubsQueue = dispatch_queue_create("stubsQueue", DISPATCH_QUEUE_SERIAL);
        _mutableRequests = [NSMutableArray array];
        _hooks = [NSMutableArray array];
        _stubbingAllowed = YES;
        _stubbingDisallowedMessage = @"";
        [self registerHook:[[LSNSURLHook alloc] init]];
        if (NSClassFromString(@"NSURLSession") != nil) {
            [self registerHook:[[LSNSURLSessionHook alloc] init]];
        }
        [self registerHook:[[LSASIHTTPRequestHook alloc] init]];
    }
    return self;
}

- (NSArray *)stubbedRequests {
    return [NSArray arrayWithArray:self.mutableRequests];
}

- (void)start {
    if (!self.isStarted){
        [self loadHooks];
        self.started = YES;
    }
}

- (void)stop {
    [self unloadHooks];
    [self clearStubs];
    self.started = NO;
}

- (void)allowStubbing {
    self.stubbingAllowed = YES;
}

- (void)disallowStubbingWithMessage:(NSString *)message {
    self.stubbingAllowed = NO;
    self.stubbingDisallowedMessage = message;
}

- (void)addStubbedRequest:(LSStubRequest *)request {
    if (!self.stubbingAllowed) {
        [NSException raise:@"NocillaStubbingDisallowedException" format:@"%@", self.stubbingDisallowedMessage];
    }

    NSUInteger index = [self.mutableRequests indexOfObject:request];

    if (index == NSNotFound) {
        [self.mutableRequests addObject:request];
        return;
    }

    [self.mutableRequests replaceObjectAtIndex:index withObject:request];
}

- (void)clearStubs {
    [self clearStubsWithBlock:nil];
}

- (void)clearStubsWithBlock:(void (^)())block {
    dispatch_sync(self.stubsQueue, ^{
        [self.mutableRequests removeAllObjects];

        if (block) {
            block();
        }
    });
}

- (LSStubResponse *)responseForRequest:(id<LSHTTPRequest>)actualRequest {
    __block NSArray* requests;

    dispatch_sync(self.stubsQueue, ^{
        requests = [[LSNocilla sharedInstance].stubbedRequests copy];
    });

    for(LSStubRequest *someStubbedRequest in requests) {
        if ([someStubbedRequest matchesRequest:actualRequest]) {
            return someStubbedRequest.response;
        }
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        [NSException raise:@"NocillaUnexpectedRequest" format:@"An unexpected HTTP request was fired.\n\nUse this snippet to stub the request:\n%@\n", [[[LSHTTPRequestDSLRepresentation alloc] initWithRequest:actualRequest] description]];
    });

    return nil;
}

- (void)registerHook:(LSHTTPClientHook *)hook {
    if (![self hookWasRegistered:hook]) {
        [[self hooks] addObject:hook];
    }
}

- (BOOL)hookWasRegistered:(LSHTTPClientHook *)aHook {
    for (LSHTTPClientHook *hook in self.hooks) {
        if ([hook isMemberOfClass: [aHook class]]) {
            return YES;
        }
    }
    return NO;
}
#pragma mark - Private
- (void)loadHooks {
    for (LSHTTPClientHook *hook in self.hooks) {
        [hook load];
    }
}

- (void)unloadHooks {
    for (LSHTTPClientHook *hook in self.hooks) {
        [hook unload];
    }
}

@end
