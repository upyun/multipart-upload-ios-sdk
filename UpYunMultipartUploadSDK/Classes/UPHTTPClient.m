//
//  UPHTTPClient.m
//  UPYUNSDK
//
//  Created by DING FENG on 11/30/15.
//  Copyright © 2015 DING FENG. All rights reserved.
//

#import "UPHTTPClient.h"


@interface UPHTTPClient() <NSURLSessionDelegate>
{
    NSTimeInterval _timeInterval;
    NSMutableDictionary *_headers;
    ProgressBlock _progressBlock;
    SuccessBlock _successBlock;
    FailureBlock _failureBlock;
    NSURLSessionTask *_sessionTask;
    NSMutableData *_didReceiveData;
    NSURLResponse *_didReceiveResponse;
    BOOL _didCompleted;
}

@end


@implementation UPHTTPClient

- (id)init {
    self = [super init];
    if (self) {
        _didCompleted = NO;
        _headers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
}

- (void)cancel {
    [_sessionTask cancel];
}

- (void)sendMultipartFormRequestWithMethod:(NSString *)method
                                       url:(NSString *)urlString
                                parameters:(NSDictionary *)formParameters
                            filePathOrData:(id)filePathOrData
                                 fieldName:(NSString *)name
                                  fileName:(NSString *)filename
                                 mimeTypes:(NSString *)mimeType
                                   success:(SuccessBlock)successBlock
                                   failure:(FailureBlock)failureBlock
                                  progress:(ProgressBlock)progressBlock {
    NSData *fileData;
    if ([filePathOrData isKindOfClass:[NSString class]]) {
        fileData = [NSData dataWithContentsOfFile:(NSString *)filePathOrData];
    } else {
        fileData = (NSData *)filePathOrData;
    }

    if (!name) {
        name = @"file";
    }
    if (!filename) {
        filename = @"filename";
    }
    if (!mimeType) {
        mimeType = @"application/octet-stream";
    }
    _progressBlock = progressBlock;
    _successBlock = successBlock;
    _failureBlock = failureBlock;
    NSString *boundary = @"UpYunSDKFormBoundaryFriSep25V01";
    boundary = [NSString stringWithFormat:@"%@%u", boundary,  arc4random() & 0x7FFFFFFF];
    NSMutableData *body = [NSMutableData data];
    for (NSString *key in formParameters) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary]
                          dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key]
                          dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@\r\n", [formParameters objectForKey:key]]
                          dataUsingEncoding:NSUTF8StringEncoding]];
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (fileData) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary]
                          dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n",name, filename]
                          dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", mimeType]
                          dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[[NSString stringWithFormat:@"\r\n"]
                          dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    //设置URLRequest
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    if (_headers) {
        for (NSString *key in _headers) {
            [request setValue:[_headers objectForKey:key] forHTTPHeaderField:key];
        }
    }
    request.HTTPBody = body;
    request.timeoutInterval = _timeInterval;
    //设置Session
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.HTTPAdditionalHeaders = @{@"Accept"        : @"application/json",
                                                   @"Content-Type"  : [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]};

    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                                          delegate:self
                                                     delegateQueue:nil];
    //发起请求
    _sessionTask = [session dataTaskWithRequest:request];
    [_sessionTask resume];
}

- (void)sendURLFormEncodedRequestWithMethod:(NSString *)methed
                                        url:(NSString *)urlString
                                 parameters:(NSDictionary *)formParameters
                                    success:(SuccessBlock)successBlock
                                    failure:(FailureBlock)failureBlock {
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:nil];
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest *request = (NSMutableURLRequest *)[NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    NSMutableString *postParameters = [NSMutableString new];
    for (NSString *key in formParameters.allKeys) {
        NSString *keyValue = [NSString stringWithFormat:@"&%@=%@",key, [formParameters objectForKey:key]];
        [postParameters appendString:keyValue];
    }
    NSData *postData = [NSData data];
    if (postParameters.length > 1) {
        postData = [[postParameters substringFromIndex:1] dataUsingEncoding:NSUTF8StringEncoding];
    }

    request.HTTPBody = postData;
    _sessionTask = [session dataTaskWithRequest:request
                              completionHandler:^(NSData *data,
                                                  NSURLResponse *response,
                                                  NSError *error) {
                                  if (error) {
                                      failureBlock(error, response, data);
                                  } else {
                                      //判断返回状态码错误。
                                      NSInteger statusCode =((NSHTTPURLResponse *)response).statusCode;
                                      NSIndexSet *succesStatus = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];
                                      if ([succesStatus containsIndex:statusCode]) {
                                          successBlock(self, response, data);
                                      } else {

                                          NSString *errorString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                          NSError *erro = [[NSError alloc] initWithDomain:@"UPHTTPClient"
                                                                                     code:0
                                                                                 userInfo:@{NSLocalizedDescriptionKey:errorString}];
                                          failureBlock(erro, response, data);
                                      }
                                  }
                              }];
    [_sessionTask resume];
}

#pragma mark NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    dispatch_async(dispatch_get_main_queue(), ^(){
        if (!_didCompleted) {
            if (_progressBlock) {
                _progressBlock(totalBytesSent, totalBytesExpectedToSend);
            }
        }
    });
}

-(void)URLSession:(NSURLSession *)session
             task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    _didCompleted = YES;
    dispatch_async(dispatch_get_main_queue(), ^(){
        if (error) {
            if (_failureBlock) {
                _failureBlock(error, _didReceiveResponse, _didReceiveData);
            }

        } else {
            //判断返回状态码错误。
            NSInteger statusCode =((NSHTTPURLResponse *)_didReceiveResponse).statusCode;
            NSIndexSet *succesStatus = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];
            if ([succesStatus containsIndex:statusCode]) {

                if (_successBlock) {
                    _successBlock(self, _didReceiveResponse, _didReceiveData);
                }

            } else {

                NSString *errorString = [[NSString alloc] initWithData:_didReceiveData encoding:NSUTF8StringEncoding];
                NSError *error = [[NSError alloc] initWithDomain:@"UPHTTPClient"
                                                            code:0
                                                        userInfo:@{NSLocalizedDescriptionKey:errorString}];
                if (_failureBlock) {
                    _failureBlock(error, _didReceiveResponse, _didReceiveData);
                }
            }
        }
        _sessionTask = nil;
        _progressBlock = nil;
        _successBlock = nil;
        _failureBlock = nil;
        _didReceiveData = nil;
        _didReceiveData = nil;
        _didReceiveResponse = nil;

    });
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {

    completionHandler(NSURLSessionResponseAllow);
    _didReceiveResponse = response;
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (_didReceiveData) {
        [_didReceiveData appendBytes:data.bytes length:data.length];
    } else {
        _didReceiveData = [[NSMutableData alloc] init];
        [_didReceiveData appendBytes:data.bytes length:data.length];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                             NSURLCredential *credential))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {

        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    }
}

#pragma NSProgress KVO

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"fractionCompleted"]) {
        NSProgress *progress = (NSProgress *)object;
        if (_progressBlock) {
            _progressBlock(progress.completedUnitCount, progress.totalUnitCount);
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


@end
