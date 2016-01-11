//
//  UMUUploaderManager.m
//  UpYunMultipartUploadSDK
//
//  Created by Jack Zhou on 6/10/14.
//
//

#import "UMUUploaderManager.h"
#import "NSData+MD5Digest.h"
#import "NSString+Base64Encode.h"
#import "NSString+NSHash.h"
#import "UPHTTPClient.h"


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
@property(nonatomic,strong)UMUUploaderOperation * umuOperation;
@end
@implementation UMUUploaderManager

- (instancetype)initWithBucket:(NSString *)bucket
{
    if (self = [super init]) {
        self.bucket = bucket;
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
        [manager.umuOperation canncel];
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
                           progressBlock:(void (^)(float percent,
                                                   long long requestDidSendBytes))progressBlock
                           completeBlock:(void (^)(NSError * error,
                                                   NSDictionary * result,
                                                   BOOL completed))completeBlock
{
    NSArray * blocks = [UMUUploaderManager subDatasWithFileData:fileData];

    __weak typeof(self)weakSelf = self;
    __block float totalPercent = 0;

    __block int blockFailed = 0;
    __block int blockSuccess = 0;


    id prepareUploadCompletedBlock = ^(NSError * error,
                                       NSDictionary * result,
                                       BOOL completed) {
        if (!completed) {
            completeBlock(error,nil,NO);
        } else {
            if ([result isKindOfClass:[NSData class]]){
                NSData *data = (NSData*)result;
                result =  [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:nil];
            }
            NSString * saveToken = result[@"save_token"];
            NSArray * filesStatus = result[@"status"];
            NSString * tokenSecret = result[@"token_secret"];
            NSMutableArray * remainingFileBlockIndexs = [[NSMutableArray alloc]init];
            NSMutableArray *progressArray = [NSMutableArray new];

            for (int i=0 ; i<filesStatus.count; i++) {
                [progressArray addObject:filesStatus[i]];
                if (![filesStatus[i]boolValue]) {
                    [remainingFileBlockIndexs addObject:@(i)];

                }
            }

            id mergeRequestCompleteBlcok =^(NSError *error, NSDictionary *result, BOOL completed) {
                if (completeBlock) {

                    dispatch_async(dispatch_get_main_queue(), ^()
                                   {
                                       if (completed) {
                                           if ([result isKindOfClass:[NSDictionary class]]) {
                                               completeBlock(nil, result, YES);
                                           } else {
                                               NSError *error;
                                               NSDictionary *json = [NSJSONSerialization JSONObjectWithData:(NSData *)result options:kNilOptions error:&error];
                                               if (json == nil) {
                                                   completeBlock(error, nil, YES);
                                               } else {
                                                   completeBlock(nil, json, YES);
                                               }
                                           }
                                       }else {
                                           completeBlock(error, nil, NO);
                                       }

                                   });

                }
            };


            for (NSNumber * num in remainingFileBlockIndexs) {
                NSData * blockData = [blocks objectAtIndex:[num intValue]];
                id singleUploadProgressBlcok = ^(float percent) {
                    if (progressBlock) {
                        @synchronized(progressArray) {
                            progressArray[[num intValue]] = [NSNumber numberWithFloat:percent];
                            float sumPercent = 0;
                            for (NSNumber *num in progressArray) {
                                sumPercent += [num floatValue];
                            }
                            totalPercent = sumPercent/progressArray.count;

                            dispatch_async(dispatch_get_main_queue(), ^() {
                                if (totalPercent) {
                                    progressBlock(totalPercent, fileData.length);
                                }
                            });
                        }
                    }
                };


                id singleUploadCompleteBlock = ^(NSError *error, NSDictionary *result, BOOL completed) {
                    if (!completed) {
                        if (completeBlock) {
                            completeBlock(error,nil,NO);

                        }
                        return ;
                    }

                    if (completed) {
                        blockSuccess++;
                    } else {
                        blockFailed++;
                    }

                    if (blockFailed < 1 && blockSuccess == remainingFileBlockIndexs.count) {
                        [weakSelf fileMergeRequestWithSaveToken:saveToken
                                                    tokenSecret:tokenSecret
                                                     retryCount:0
                                                  completeBlock:mergeRequestCompleteBlcok];
                    }
                };
                [weakSelf uploadFileBlockWithSaveToken:saveToken
                                            blockIndex:[num intValue]
                                         fileBlockData:blockData
                                            retryTimes:0
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
    NSDictionary * parameters = @{@"policy":uploadPolicy,
                                  @"signature":[weakSelf createSignatureWithToken:tokenSecret
                                                                       parameters:policyParameters]};
    UPHTTPClient *upHttpClient = [[UPHTTPClient alloc] init];
    NSURL * url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", API_SERVER, self.bucket]];
    [upHttpClient sendMultipartFormRequestWithMethod:@"POST"
                                                 url:url.absoluteString
                                          parameters:parameters
                                      filePathOrData:fileBlockData
                                           fieldName:@"file"
                                            fileName:@"filename"
                                           mimeTypes:@"application/octet-stream"
                                             success:^(UPHTTPClient *upHttpClient, NSURLResponse *response, id responseObject) {
                                                 NSError *error;
                                                 NSDictionary *json = [NSJSONSerialization JSONObjectWithData:responseObject
                                                                                                      options:kNilOptions
                                                                                                        error:&error];

                                                 if (error) {
                                                     NSLog(@"error %@", error);
                                                     completeBlock(error, nil, NO);
                                                 } else {
                                                     completeBlock(error, json, YES);
                                                 }

                                             }
                                             failure:^(NSError *error, NSURLResponse *response, id responseObject) {
                                                 completeBlock(error, nil, NO);
                                             }
                                            progress:^(long long completedBytesCount, long long totalBytesCount) {
                                                @synchronized(self) {
                                                    float k = (float)completedBytesCount / totalBytesCount;
                                                    if (progressBlock) {
                                                        progressBlock(k);
                                                    }
                                                }
                                            }];
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

- (void)ministrantRequestWithSignature:(NSString *)signature
                                policy:(NSString *)policy
                         completeBlock:(void (^)(NSError * error,
                                                 NSDictionary * result,
                                                 BOOL completed))completeBlock {

    NSDictionary * requestParameters = @{@"policy":policy,
                                         @"signature":signature};
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:nil delegateQueue:nil];
    NSURL * url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", API_SERVER, self.bucket]];
    NSMutableURLRequest *request = (NSMutableURLRequest *)[NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    NSMutableString *postParameters = [[NSMutableString alloc] init];
    for (NSString *key in requestParameters.allKeys) {
        NSString *keyValue = [NSString stringWithFormat:@"&%@=%@",key, [requestParameters objectForKey:key]];
        [postParameters appendString:keyValue];
    }
    NSData *postData = [NSData data];
    if (postParameters.length > 1) {
        postData = [[postParameters substringFromIndex:1] dataUsingEncoding:NSUTF8StringEncoding];
    }
    request.HTTPBody = postData;
    NSURLSessionTask *_sessionTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data,
                                                                    NSURLResponse *response,
                                                                    NSError *error) {
                                                    if (error) {
                                                        completeBlock(error, nil, NO);
                                                    } else {
                                                        //判断返回状态码错误。
                                                        NSInteger statusCode =((NSHTTPURLResponse *)response).statusCode;
                                                        NSIndexSet *succesStatus = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];
                                                        if ([succesStatus containsIndex:statusCode]) {

                                                            NSError *error;
                                                            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                                                            if (json == nil) {
                                                                completeBlock(error, nil, NO);
                                                            } else {
                                                                completeBlock(nil, json, YES);
                                                            }
                                                        } else {
                                                            NSString *errorString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                                            NSError *erro = [[NSError alloc] initWithDomain:@"UPHTTPClient"
                                                                                                       code:0
                                                                                                   userInfo:@{NSLocalizedDescriptionKey:errorString}];
                                                            completeBlock(erro, nil, NO);
                                                        }
                                                    }
                                                }];
    [_sessionTask resume];
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
