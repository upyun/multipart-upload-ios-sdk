//
//  UMUUploaderOperation.h
//  UpYunMultipartUploadSDK
//
//  Created by Jack Zhou on 6/10/14.
//
//

#import <Foundation/Foundation.h>
#import <AFNetworking.h>
@interface UMUUploaderOperation : NSObject
@property(nonatomic, strong, readonly)NSArray * operations;
- (void)addOperation:(AFHTTPRequestOperation *)operation;

- (void)canncel;
@end
