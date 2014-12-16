//
//  UMUUploaderOperation.m
//  UpYunMultipartUploadSDK
//
//  Created by Jack Zhou on 6/10/14.
//
//

#import "UMUUploaderOperation.h"
@interface UMUUploaderOperation()
@property(nonatomic, strong, readwrite)NSArray * operations;
@end
@implementation UMUUploaderOperation

- (void)addOperation:(AFHTTPRequestOperation *)operation
{
    NSMutableArray * mutabelArray = [NSMutableArray arrayWithArray:self.operations];
    [mutabelArray addObject:operation];
    self.operations = mutabelArray;
}

- (void)canncel
{
    for (AFHTTPRequestOperation * operation in self.operations) {
        [operation cancel];
    }
}
@end
