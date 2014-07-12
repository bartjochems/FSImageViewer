//  FSImageViewer
//
//  Created by Felix Schulze on 8/26/2013.
//  Copyright 2013 Felix Schulze. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import <EGOCache/EGOCache.h>
#import "FSImageLoader.h"
#import "AFImageRequestOperation.h"

@implementation FSImageLoader {
    NSMutableArray *runningRequests;
}

+ (FSImageLoader *)sharedInstance {
    static FSImageLoader *sharedInstance = nil;
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[FSImageLoader alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.timeoutInterval = 30.0;
        runningRequests = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void)dealloc {
    [self cancelAllRequests];
}

- (void)cancelAllRequests {
    for (AFImageRequestOperation *imageRequestOperation in runningRequests) {
        [imageRequestOperation cancel];
    }
}

- (void)cancelRequestForUrl:(NSURL *)aURL {
    for (AFImageRequestOperation *imageRequestOperation in runningRequests) {
        if ([imageRequestOperation.request.URL isEqual:aURL]) {
            [imageRequestOperation cancel];
            break;
        }
    }
}

- (void)loadImageForURL:(NSURL *)aURL image:(void (^)(UIImage *image, NSError *error))imageBlock {

    if (!aURL) {
        NSError *error = [NSError errorWithDomain:@"de.felixschulze.fsimageloader" code:412 userInfo:@{
                NSLocalizedDescriptionKey : @"You must set a url"
        }];
        imageBlock(nil, error);
    };
    NSString *cacheKey = [NSString stringWithFormat:@"FSImageLoader-%u", [[aURL description] hash]];

    UIImage *anImage = [[EGOCache globalCache] imageForKey:cacheKey];

    if (anImage) {
        if (imageBlock) {
            imageBlock(anImage, nil);
        }
    }
    else {
        [self cancelRequestForUrl:aURL];

        NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:aURL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:_timeoutInterval];
        
        NSString *username = [[LUKeychainAccess standardKeychainAccess] stringForKey:@"username"];
        NSString *password = [[LUKeychainAccess standardKeychainAccess] stringForKey:@"password"];
        
        NSString *basicAuthCredentials = [NSString stringWithFormat:@"%@:%@", username, password];
        NSString *auth = [NSString stringWithFormat:@"Basic %@", [self base64Encoding:basicAuthCredentials]];
        
        [urlRequest addValue:auth forHTTPHeaderField:@"Authorization"];
        
        AFImageRequestOperation *imageRequestOperation = [[AFImageRequestOperation alloc] initWithRequest:urlRequest];
        [runningRequests addObject:imageRequestOperation];

        __weak AFImageRequestOperation *imageRequestOperationForBlock = imageRequestOperation;
        [imageRequestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            UIImage *image = responseObject;
            [[EGOCache globalCache] setImage:image forKey:cacheKey];
            if (imageBlock) {
                imageBlock(image, nil);
            }
            [runningRequests removeObject:imageRequestOperationForBlock];
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            if (imageBlock) {
                imageBlock(nil, error);
            }
            [runningRequests removeObject:imageRequestOperationForBlock];
        }];

        [imageRequestOperation start];
    }
}

- (NSString *)base64Encoding:(NSString *)string {
    NSData *data = [NSData dataWithBytes:[string UTF8String] length:[string lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    NSUInteger length = [data length];
    NSMutableData *mutableData = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
    
    uint8_t *input = (uint8_t *)[data bytes];
    uint8_t *output = (uint8_t *)[mutableData mutableBytes];
    
    for (NSUInteger i = 0; i < length; i += 3) {
        NSUInteger value = 0;
        for (NSUInteger j = i; j < (i + 3); j++) {
            value <<= 8;
            if (j < length) {
                value |= (0xFF & input[j]);
            }
        }
        
        static uint8_t const kAFBase64EncodingTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        
        NSUInteger idx = (i / 3) * 4;
        output[idx + 0] = kAFBase64EncodingTable[(value >> 18) & 0x3F];
        output[idx + 1] = kAFBase64EncodingTable[(value >> 12) & 0x3F];
        output[idx + 2] = (i + 1) < length ? kAFBase64EncodingTable[(value >> 6)  & 0x3F] : '=';
        output[idx + 3] = (i + 2) < length ? kAFBase64EncodingTable[(value >> 0)  & 0x3F] : '=';
    }
    
    return [[NSString alloc] initWithData:mutableData encoding:NSASCIIStringEncoding];
}

@end