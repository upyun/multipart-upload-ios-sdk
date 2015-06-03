//
//  UMUUploaderManager.m
//  UpYunMultipartUploadSDK
//
//  Created by Jack Zhou on 6/10/14.
//
//

#import "UMUUploaderManager.h"
#import <AFNetworking.h>
#import "NSData+MD5Digest.h"
#import "NSString+Base64Encode.h"
#import "NSString+NSHash.h"
#if __has_include("AFHTTPClient.h")
#define AF_1_3_4
#endif
static NSString * UMU_ERROR_DOMAIN = @"UMUErrorDomain";

/**
 *  请求api地址
 */
static NSString * API_SERVER = @"http://m0.api.upyun.com/";

/**
 *  单个分块尺寸100kb(不可小于此值)
 */
static NSInteger SingleBlockSize = 1024*100;

/**
 *  同一个bucket 上传文件时最大并发请求数
 */
static NSInteger MaxConcurrentOperationCount = 1;

/**
 *   默认授权时间长度（秒)
 */
static NSInteger ValidTimeSpan = 60.0f;

/**
 *   请求重试次数
 */
static NSInteger MaxRetryCount  = 3;

static NSMutableDictionary * managerRepository;

@interface UMUUploaderManager()
@property(nonatomic,copy)NSString * bucket;
#ifdef AF_1_3_4
@property(nonatomic,strong)AFHTTPClient * afClient;
#else
@property(nonatomic,strong)AFHTTPRequestOperationManager * afManager;
#endif
@property(nonatomic,strong)UMUUploaderOperation * umuOperation;
@end
@implementation UMUUploaderManager

- (instancetype)initWithBucket:(NSString *)bucket
{
    if (self = [super init]) {
        self.bucket = bucket;
        NSURL * baseUrl = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", API_SERVER, bucket]];
#ifdef AF_1_3_4
        self.afClient = [[AFHTTPClient alloc]initWithBaseURL:baseUrl];
        self.afClient.operationQueue.maxConcurrentOperationCount = MaxConcurrentOperationCount;
#else
        self.afManager = [[AFHTTPRequestOperationManager alloc]initWithBaseURL:baseUrl];
        self.afManager.operationQueue.maxConcurrentOperationCount = MaxConcurrentOperationCount;
#endif
    }
    return self;
}

+ (instancetype)managerWithBucket:(NSString *)bucket
{
    if (!managerRepository) {
        managerRepository = [[NSMutableDictionary alloc] init];
    }
    bucket = [self formatBucket:bucket];
    if (!managerRepository[bucket]) {
        UMUUploaderManager * manager = [[self alloc] initWithBucket:bucket];
        managerRepository[bucket] = manager;
        manager.umuOperation = [[UMUUploaderOperation alloc]init];
    }
    return managerRepository[bucket];
}

#pragma mark - Setup Methods

+ (void)setValidTimeSpan:(NSInteger)validTimeSpan
{
    ValidTimeSpan = validTimeSpan;
}

+ (void)setServer:(NSString *)server
{
    API_SERVER = server;
}

+ (void)setMaxRetryCount:(NSInteger)retryCount
{
    MaxRetryCount = retryCount;
}

#pragma mark - Public Methods

+ (void)cancelAllOperations
{
    for (NSString * key in managerRepository.allKeys) {
        UMUUploaderManager * manager = managerRepository[key];
#ifdef AF_1_3_4
        [manager.afClient.operationQueue cancelAllOperations];
#else
        [manager.afManager.operationQueue cancelAllOperations];
#endif
    
    }
}

+ (NSDictionary *)fetchFileInfoDictionaryWith:(NSData *)fileData
{
    NSInteger blockCount = [self calculateBlockCount:fileData];
    NSDictionary * parameters = @{@"file_blocks":@(blockCount),
                                  @"file_hash":[fileData MD5HexDigest],
                                  @"file_size":@(fileData.length)};
    return parameters;
}

- (UMUUploaderOperation *)uploadWithFile:(NSData *)fileData
                                  policy:(NSString *)policy
                               signature:(NSString *)signature
                           progressBlock:(void (^)(CGFloat percent,
                                                   long long requestDidSendBytes))progressBlock
                           completeBlock:(void (^)(NSError * error,
                                                   NSDictionary * result,
                                                   BOOL completed))completeBlock
{
    NSArray * blocks = [UMUUploaderManager subDatasWithFileData:fileData];
    __block NSInteger failedCount = 0;
    __block NSInteger successCount = 0;
    __block NSError * resultError;
    __weak typeof(self)weakSelf = self;
    id prepareUploadCompletedBlock = ^(NSError * error,
                                       NSDictionary * result,
                                       BOOL completed) {
        if (!completed) {
            completeBlock(error,nil,NO);
        }else {
            if ([result isKindOfClass:[NSData class]]){
                NSData *data = (NSData*)result;
                result =  [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:nil];
            }
            NSString * saveToken = result[@"save_token"];
            NSArray * filesStatus = result[@"status"];
            NSString * tokenSecret = result[@"token_secret"];
            NSMutableArray * remainingFileBlockIndexs = [[NSMutableArray alloc]init];
            __block float totalPercent = 0;
            float uploadedPercent = 1.0f;
            for (int i=0 ; i<filesStatus.count; i++) {
                if (![filesStatus[i]boolValue]) {
                    [remainingFileBlockIndexs addObject:@(i)];
                    uploadedPercent-=1.0/filesStatus.count;
                }
            }
            
            id mergeRequestCompleteBlcok =^(NSError *error, NSDictionary *result, BOOL completed) {
                if (completeBlock) {
                    if (completed) {
                        completeBlock(nil, result, YES);
                    }else {
                        completeBlock(error, nil, NO);
                    }
                }
            };
            
            if (uploadedPercent == 1.0f) {
                [weakSelf fileMergeRequestWithSaveToken:saveToken
                                            tokenSecret:tokenSecret
                                             retryCount:0
                                          completeBlock:mergeRequestCompleteBlcok];
                return;
            }
            NSMutableDictionary * progressDic = [[NSMutableDictionary alloc]init];
            for (NSNumber * num in remainingFileBlockIndexs) {
                NSData * blockData = [blocks objectAtIndex:[num intValue]];
                id singleUploadProgressBlcok = ^(float percent) {
                    totalPercent = totalPercent+percent/filesStatus.count;
                    if (progressBlock) {
                        progressBlock(totalPercent+uploadedPercent, fileData.length);
                    }
                };
                
                id singleUploadCompleteBlock = ^(NSError *error, NSDictionary *result, BOOL completed) {
                    if (completed) {
                        successCount++;
                    }else{
                        failedCount++;
                        resultError = error;
                    }
                    if ((failedCount+successCount == remainingFileBlockIndexs.count) && failedCount == 0) {
                        [weakSelf fileMergeRequestWithSaveToken:saveToken
                                                    tokenSecret:tokenSecret
                                                     retryCount:0
                                                  completeBlock:mergeRequestCompleteBlcok];
                    }else if((failedCount+successCount == remainingFileBlockIndexs.count) && failedCount != 0) {
                        if (completeBlock) {
                            completeBlock(resultError,nil,NO);
                        }
                    }
                };
                [weakSelf uploadFileBlockWithSaveToken:saveToken
                                            blockIndex:[num intValue]
                                         fileBlockData:blockData
                                            retryTimes:0
                                           progressDic:progressDic
                                           tokenSecret:tokenSecret
                                         progressBlock:singleUploadProgressBlcok
                                         completeBlock:singleUploadCompleteBlock];
            }
        }
    };
    [self prepareUploadRequestWithPolicy:policy
                               signature:signature
                              retryCount:0
                           completeBlock:prepareUploadCompletedBlock];
    return self.umuOperation;
}

#pragma mark - Private Methods

- (void)prepareUploadRequestWithPolicy:(NSString *)policy
                             signature:(NSString *)signature
                            retryCount:(NSInteger)retryCount
                         completeBlock:(void (^)(NSError * error,
                                                 NSDictionary * result,
                                                 BOOL completed))completeBlock
{
    __block typeof(retryCount)blockRetryCount = retryCount;
    __weak typeof(self)weakSelf = self;
    [self ministrantRequestWithSignature:signature
                                  policy:policy
                           completeBlock:^(NSError *error,
                                           NSDictionary *result,
                                           BOOL completed) {
        if (completeBlock) {
            completeBlock(error,result,completed);
        }else if(retryCount >= MaxRetryCount) {
            completeBlock(error, nil, NO);
        }else {
            blockRetryCount++;
            [weakSelf prepareUploadRequestWithPolicy:policy
                                           signature:signature
                                          retryCount:blockRetryCount
                                       completeBlock:completeBlock];
        }
    }];
    
}

- (void)uploadFileBlockWithSaveToken:(NSString *)saveToken
                          blockIndex:(NSInteger)blockIndex
                       fileBlockData:(NSData *)fileBlockData
                          retryTimes:(NSInteger)retryTimes
                         progressDic:(NSMutableDictionary *)progressDic
                         tokenSecret:(NSString *)tokenSecret
                       progressBlock:(void (^)(float percent))progressBlock
                       completeBlock:(void (^)(NSError * error,
                                                                   NSDictionary * result,
                                                                   BOOL completed))completeBlock
{
    NSDictionary * policyParameters = @{@"save_token":saveToken,
                                        @"expiration":@(ceil([[NSDate date] timeIntervalSince1970]+ValidTimeSpan)),
                                        @"block_index":@(blockIndex),
                                        @"block_hash":[fileBlockData MD5HexDigest]};
    NSString * uploadPolicy = [self dictionaryToJSONStringBase64Encoding:policyParameters];
    
    __weak typeof(self)weakSelf = self;
    __block typeof(retryTimes)blockRetryTime = retryTimes;
    __block NSString * key = [NSString stringWithFormat:@"%ld",(long)blockIndex];
    id constructingBodyWithBlock = ^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFileData:fileBlockData
                                    name:@"file"
                                fileName:@"file"
                                mimeType:@"file"];
    };
    id successBlock = ^(AFHTTPRequestOperation *operation, id responseObject) {
        progressBlock(1);
        NSError * error = [weakSelf checkResultWithResponseObject:responseObject
                                                         response:operation.response];
        if (error && completeBlock) {
            if (retryTimes >= MaxRetryCount) {
                completeBlock(error,nil,NO);
            }else {
                blockRetryTime++;
                [weakSelf uploadFileBlockWithSaveToken:saveToken
                                            blockIndex:blockIndex
                                         fileBlockData:fileBlockData
                                            retryTimes:blockRetryTime
                                           progressDic:progressDic
                                           tokenSecret:tokenSecret
                                         progressBlock:progressBlock
                                         completeBlock:completeBlock];

            }
        }else if (completeBlock) {
            completeBlock(nil,responseObject,YES);
        }
    };
    
    id failureBlock = ^(AFHTTPRequestOperation *operation, NSError *error) {
        float percent = [[progressDic objectForKey:key] floatValue];
        progressBlock(-percent);
        if (retryTimes >= MaxRetryCount) {
            if (operation.responseData) {
                NSDictionary * responseObject = [NSJSONSerialization JSONObjectWithData:operation.responseData
                                                                                options:NSJSONReadingMutableLeaves
                                                                                  error:nil];
                if (responseObject[@"error_code"]) {
                    NSHTTPURLResponse * response = operation.response;
                    NSMutableDictionary * userInfo = [NSMutableDictionary dictionary];
                    if (response.allHeaderFields) {
                        userInfo[@"allHeaderFields"] = response.allHeaderFields;
                        userInfo[@"statusCode"] = @(response.statusCode);
                    }
                    userInfo[NSLocalizedDescriptionKey] = responseObject[@"message"];
                    error = [NSError errorWithDomain:UMU_ERROR_DOMAIN
                                                code:[responseObject[@"error_code"] integerValue]
                                            userInfo:userInfo];
                }
            }
            completeBlock(error,nil,NO);
        }else {
            blockRetryTime++;
            [weakSelf uploadFileBlockWithSaveToken:saveToken
                                        blockIndex:blockIndex
                                     fileBlockData:fileBlockData
                                        retryTimes:blockRetryTime
                                       progressDic:progressDic
                                       tokenSecret:tokenSecret
                                     progressBlock:progressBlock
                                     completeBlock:completeBlock];
        }
    };
    NSDictionary * parameters = @{@"policy":uploadPolicy,
                                  @"signature":[weakSelf createSignatureWithToken:tokenSecret
                                                                       parameters:policyParameters]};
#ifdef AF_1_3_4
    NSMutableURLRequest *request =  [self.afClient multipartFormRequestWithMethod:@"POST"
                                                                             path:@""
                                                                       parameters:parameters
                                                        constructingBodyWithBlock:constructingBodyWithBlock];
    AFHTTPRequestOperation *uploadOperation = [self.afClient HTTPRequestOperationWithRequest:request
                                                                                     success:successBlock
                                                                                     failure:failureBlock];
#else
    AFHTTPRequestOperation *uploadOperation  = [self.afManager POST:@""
                                                         parameters:parameters
                                          constructingBodyWithBlock:constructingBodyWithBlock
                                                            success:successBlock
                                                            failure:failureBlock];
#endif
    [self.umuOperation addOperation:uploadOperation];
    [uploadOperation start];
}


- (void)fileMergeRequestWithSaveToken:(NSString *)saveToken
                          tokenSecret:(NSString *)tokenSecret
                           retryCount:(NSInteger)retryCount
                        completeBlock:(void (^)(NSError * error,
                                                NSDictionary * result,
                                                BOOL completed))completeBlock
{
    __weak typeof(self)weakSelf = self;
    __block typeof(retryCount)blockRetryCount = retryCount;
    NSDictionary * parameters = @{@"save_token":saveToken,
                                  @"expiration":@(ceil([[NSDate date] timeIntervalSince1970]+60))};
    NSString * mergePolicy = [self dictionaryToJSONStringBase64Encoding:parameters];
    [self ministrantRequestWithSignature:[self createSignatureWithToken:tokenSecret
                                                                    parameters:parameters]
                                         policy:mergePolicy
                                  completeBlock:^(NSError *error, NSDictionary *result, BOOL completed) {
                                      if (completeBlock) {
                                          completeBlock(error,result,completed);
                                      }else if(retryCount >= MaxRetryCount) {
                                          completeBlock(error, nil, NO);
                                      }else {
                                          blockRetryCount++;
                                          [weakSelf fileMergeRequestWithSaveToken:saveToken
                                                                      tokenSecret:tokenSecret
                                                                       retryCount:blockRetryCount
                                                                    completeBlock:completeBlock];
                                      }

                                  }];
}

- (AFHTTPRequestOperation *)ministrantRequestWithSignature:(NSString *)signature
                                                    policy:(NSString *)policy
                                             completeBlock:(void (^)(NSError * error,
                                                                     NSDictionary * result,
                                                                     BOOL completed))completeBlock
{
    __weak typeof(self)weakSelf = self;
    id successBlock = ^(AFHTTPRequestOperation *operation, id responseObject) {
        NSError * error = [weakSelf checkResultWithResponseObject:responseObject
                                                         response:operation.response];
        if (error && completeBlock) {
            completeBlock(error,nil,NO);
        }else if (completeBlock) {
            completeBlock(nil,responseObject,YES);
        }
    };
    
    id failureBlock = ^(AFHTTPRequestOperation *operation, NSError *error) {
        NSDictionary * allHeaderFields = operation.response.allHeaderFields;
        if (operation.responseData) {
            NSDictionary * responseObject = [NSJSONSerialization JSONObjectWithData:operation.responseData
                                                                            options:NSJSONReadingMutableLeaves
                                                                              error:nil];
            NSError * error = [weakSelf checkResultWithResponseObject:responseObject
                                                             response:operation.response];
        }
        completeBlock(error,nil,NO);
    };
    NSDictionary * requestParameters = @{@"policy":policy,
                                         @"signature":signature};
#ifdef AF_1_3_4
    NSMutableURLRequest *request = [self.afClient requestWithMethod:@"POST"
                                                               path:@""
                                                         parameters:requestParameters];
    [request setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    AFHTTPRequestOperation *ministrantOperation = [self.afClient HTTPRequestOperationWithRequest:request
                                                                                         success:successBlock
                                                                                         failure:failureBlock];
#else
    AFHTTPRequestOperation *ministrantOperation = [self.afManager POST:@"" parameters:requestParameters success:successBlock failure:failureBlock];
#endif
    [self.umuOperation addOperation:ministrantOperation];
    [ministrantOperation start];
    return ministrantOperation;
}


#pragma mark - Utils


- (NSError *)checkResultWithResponseObject:(NSDictionary *)responseObject
                                  response:(NSHTTPURLResponse*)response
{
    if ([responseObject isKindOfClass:[NSData class]]){
        NSData *data = (NSData*)responseObject;
        responseObject =  [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:nil];
    }

    if (responseObject[@"error_code"]) {
        NSMutableDictionary * userInfo = [NSMutableDictionary dictionary];
        if (response.allHeaderFields) {
            userInfo[@"allHeaderFields"] = response.allHeaderFields;
            userInfo[@"statusCode"] = @(response.statusCode);
        }
        userInfo[NSLocalizedDescriptionKey] = responseObject[@"message"];
        NSError * error = [NSError errorWithDomain:UMU_ERROR_DOMAIN
                                              code:[responseObject[@"error_code"] integerValue]
                                          userInfo:userInfo];
        return error;
    }
    return nil;
}


//计算文件块数
+ (NSInteger)calculateBlockCount:(NSData *)fileData
{
    if (fileData.length < SingleBlockSize)
        return 1;
    return ceil(fileData.length*1.0/SingleBlockSize) ;
}

//生成文件块
+ (NSArray *)subDatasWithFileData:(NSData *)fileData
{
    NSInteger blockCount = [self calculateBlockCount:fileData];
    NSInteger l = 0;
    NSMutableArray * blocks = [[NSMutableArray alloc]init];
    for (int i = 0; i < blockCount;i++ ) {
        NSInteger startLocation = i*SingleBlockSize;
        NSInteger length = SingleBlockSize;
        if (startLocation+length > fileData.length) {
            length = fileData.length-startLocation;
        }
        NSData * subData = [fileData subdataWithRange:NSMakeRange(startLocation, length)];
        [blocks addObject:subData];
        l = l+subData.length;
    }
    return blocks;
}

//根据token 计算签名
- (NSString *)createSignatureWithToken:(NSString *)token
                            parameters:(NSDictionary *)parameters
{
    NSString * signature = @"";
    NSArray * keys = [parameters allKeys];
    keys= [keys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString * key in keys) {
        NSString * value = parameters[key];
        signature = [NSString stringWithFormat:@"%@%@%@",signature,key,value];
    }
    signature = [signature stringByAppendingString:token];
    return [signature MD5];
}

- (NSString *)dictionaryToJSONStringBase64Encoding:(NSDictionary *)dic
{
    id paramesData = [NSJSONSerialization dataWithJSONObject:dic options:0 error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:paramesData
                                                 encoding:NSUTF8StringEncoding];
    return [jsonString base64encode];
}

+ (NSString *)formatBucket:(NSString *)bucket
{
    if(![bucket hasSuffix:@"/"]) {
        bucket = [bucket stringByAppendingString:@"/"];
    }
    return bucket;
}

@end
