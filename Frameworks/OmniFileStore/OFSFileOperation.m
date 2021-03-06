// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSFileOperation.h"

#import <OmniFileStore/OFSFileManager.h>

RCS_ID("$Id$");

@implementation OFSFileOperation
{
    __weak OFSFileManager *_weak_fileManager;
    NSOperationQueue *_callbackQueue;
    NSData *_data;
    BOOL _read;
    BOOL _atomically; // for writing
    NSURL *_url;

    long long _processedLength;
}

- initWithFileManager:(OFSFileManager *)fileManager readingURL:(NSURL *)url;
{
    if (!(self = [super init]))
        return nil;
    
    _weak_fileManager = fileManager;
    _url = [url copy];
    _read = YES;
    _data = nil;
    
    return self;
}

- initWithFileManager:(OFSFileManager *)fileManager writingData:(NSData *)data atomically:(BOOL)atomically toURL:(NSURL *)url;
{
    if (!(self = [super init]))
        return nil;
    
    _weak_fileManager = fileManager;
    _url = [url copy];
    _read = NO;
    _atomically = atomically;
    _data = [data copy];
    
    return self;
}


#pragma mark - ODAVAsynchronousOperation

// These callbacks should all be called with this macro
#define PERFORM_CALLBACK(callback, ...) do { \
    typeof(callback) _cb = (callback); \
    if (_cb) { \
        [_callbackQueue addOperationWithBlock:^{ \
            _cb(__VA_ARGS__); \
        }]; \
    } \
} while(0)

@synthesize didFinish = _didFinish;
@synthesize didReceiveData = _didReceiveData;
@synthesize didReceiveBytes = _didReceiveBytes;
@synthesize didSendBytes = _didSendBytes;

- (NSURL *)url;
{
    return _url;
}

- (long long)processedLength;
{
    return _processedLength;
}

- (long long)expectedLength;
{
    return [_data length];
}

- (void)startWithCallbackQueue:(NSOperationQueue *)queue;
{
    OBPRECONDITION(_didFinish); // What is the purpose of an async operation that we don't track the end of?
    OBPRECONDITION(_processedLength == 0); // Don't call more than once.
    
    if (queue)
        _callbackQueue = queue;
    else
        _callbackQueue = [NSOperationQueue currentQueue];

    OFSFileManager *fileManager = _weak_fileManager;
    if (!fileManager) {
        OBASSERT_NOT_REACHED("File manager released with unfinished operations");
        return;
    }
    
    // We do all operations synchronously by default right now.
    if (_read) {
        __autoreleasing NSError *error = nil;
        NSData *data = [fileManager dataWithContentsOfURL:_url error:&error];
        if (data == nil) {
            NSError *strongError = error;
            PERFORM_CALLBACK(_didFinish, self, strongError);
        } else {
            _processedLength = [data length];
            if (_didReceiveData) {
                PERFORM_CALLBACK(_didReceiveData, self, data);
            } else if (_didReceiveBytes) {
                PERFORM_CALLBACK(_didReceiveBytes, self, _processedLength);
            }
            PERFORM_CALLBACK(_didFinish, self, nil);
        }
    } else {
        __autoreleasing NSError *error = nil;
        if (![fileManager writeData:_data toURL:_url atomically:_atomically error:&error]) {
            NSError *strongError = error;
            PERFORM_CALLBACK(_didFinish, self, strongError);
        } else {
            _processedLength = [_data length];
            PERFORM_CALLBACK(_didSendBytes, self, _processedLength);
            PERFORM_CALLBACK(_didFinish, self, nil);
        }
    }
}

- (void)cancel;
{
    // no-op: synchronous operation-only
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

@end
