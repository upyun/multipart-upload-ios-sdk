//
//  UMUUploaderOperation.h
//  UpYunMultipartUploadSDK
//
//  Created by Jack Zhou on 6/10/14.
//
//

#import <Foundation/Foundation.h>


@interface UMUUploaderOperation : NSObject

@property(nonatomic, strong, readonly)NSArray * tasks;

- (void)addTasks:(NSURLSessionTask *)task;
- (void)canncel;

@end
