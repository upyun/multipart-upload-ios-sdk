//
//  UPHTTPClient.h
//  UPYUNSDK
//
//  Created by DING FENG on 11/30/15.
//  Copyright © 2015 DING FENG. All rights reserved.
//

#import <Foundation/Foundation.h>


@class UPHTTPClient;


typedef void(^SuccessBlock)(UPHTTPClient *upHttpClient, NSURLResponse *response, id responseObject);
typedef void(^FailureBlock)(NSError *error, NSURLResponse *response, id responseObject);
typedef void(^ProgressBlock)(long long completedBytesCount,long long totalBytesCount);


@interface UPHTTPClient : NSObject

// Multi-Part Request
- (void)sendMultipartFormRequestWithMethod:(NSString *)method
                                       url:(NSString *)urlString
                                parameters:(NSDictionary *)formParameters
                            filePathOrData:(id)filePathOrData
                                 fieldName:(NSString *)name
                                  fileName:(NSString *)filename
                                 mimeTypes:(NSString *)mimeType
                                   success:(SuccessBlock)successBlock
                                   failure:(FailureBlock)failureBlock
                                  progress:(ProgressBlock)progressBlock;


// URL-Form-Encoded Request
- (void)sendURLFormEncodedRequestWithMethod:(NSString *)methed
                                        url:(NSString *)urlString
                                 parameters:(NSDictionary *)formParameters
                                    success:(SuccessBlock)successBlock
                                    failure:(FailureBlock)failureBlock;

- (void)cancel;

@end
