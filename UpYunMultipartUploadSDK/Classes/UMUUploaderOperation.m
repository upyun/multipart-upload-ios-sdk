//
//  UMUUploaderOperation.m
//  UpYunMultipartUploadSDK
//
//  Created by Jack Zhou on 6/10/14.
//
//

#import "UMUUploaderOperation.h"


@interface UMUUploaderOperation()

@property(nonatomic, strong, readwrite)NSArray * tasks;

@end


@implementation UMUUploaderOperation

- (void)addTasks:(NSURLSessionTask *)task {
    NSMutableArray * mutabelArray = [NSMutableArray arrayWithArray:self.tasks];
    [mutabelArray addObject:task];
    self.tasks = mutabelArray;
}

- (void)canncel {
    for (NSURLSessionTask * task in self.tasks) {
        [task cancel];
    }
}

@end
