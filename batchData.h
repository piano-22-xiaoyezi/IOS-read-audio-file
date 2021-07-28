//
//  batchData.h
//
//  Created by piano on 2021/7/27.
//  Copyright © 2021 Jim. All rights reserved.
//

#ifndef batchData_h
#define batchData_h

NS_ASSUME_NONNULL_BEGIN

@interface BatchData : NSObject

+ (id)getInstance;
-(void) startBatchData;
-(void) singleAudioParser:(NSString *)audioaPath;

@end

NS_ASSUME_NONNULL_END


#endif /* batchData_h */
