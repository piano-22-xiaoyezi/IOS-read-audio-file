//
//  batchData.m
//
//  Created by piano on 2021/7/27.
//  Copyright © 2021 Jim. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "batchData.h"
#import <AudioToolbox/AudioToolbox.h>



@interface BatchData()

@end


@implementation BatchData

+ (id)getInstance {
    static BatchData *batchData;
    static dispatch_once_t oneToken;
    dispatch_once(&oneToken, ^{
        batchData = [[BatchData alloc] init];
    });
    return batchData;
}

-(void) startBatchData {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *audioaPath = [[paths objectAtIndex:0]stringByAppendingPathComponent:@"testData"];
    NSArray *subpaths = [fileManager subpathsAtPath:audioaPath];
    NSString *wavPath;
    for(int i=0; i<subpaths.count; i++) {
        NSLog(@"%@", subpaths[i]);
        if (![subpaths[i] hasSuffix:@".wav"]) { continue;}
        wavPath = [audioaPath stringByAppendingPathComponent:subpaths[i]];
        NSLog(@"%@", wavPath);
        [self singleAudioParser:wavPath];
    }
}

-(void) singleAudioParser:(NSString *)audioaPath {
    const char *cString = [audioaPath cStringUsingEncoding:NSASCIIStringEncoding];
    CFStringRef str = CFStringCreateWithCString(NULL, cString,  kCFStringEncodingMacRoman);
    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, str, kCFURLPOSIXPathStyle, false);

    ExtAudioFileRef fileRef;
    ExtAudioFileOpenURL(inputFileURL, &fileRef);
    
    AudioStreamBasicDescription audioFormat;

    audioFormat.mSampleRate = 16000; // 采样率 ：Hz
    audioFormat.mFormatID = kAudioFormatLinearPCM; // 采样数据的类型，PCM,AAC等
    //    recordFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger; // 每种格式特定的标志，无损编码 ，0表示没有
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeEndian;
    //    recordFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket = 1;  // 一个数据包中的帧数，每个packet的帧数。如果是未压缩的音频数据，值是1。动态帧率格式，这个值是一个较大的固定数字，比如说AAC的1024。如果是动态大小帧数（比如Ogg格式）设置为0。
    audioFormat.mChannelsPerFrame = 1; // 每一帧数据中的通道数，单声道为1，立体声为2
    audioFormat.mBitsPerChannel = 16; // 每个通道中的位数，1byte = 8bit
    audioFormat.mBytesPerFrame = audioFormat.mChannelsPerFrame * 2;; // 每一帧中的字节数
    audioFormat.mBytesPerPacket = audioFormat.mFramesPerPacket * audioFormat.mBytesPerFrame;; // 一个数据包中的字节数

    // 3) Apply audio format to the Extended Audio File
    ExtAudioFileSetProperty(fileRef, kExtAudioFileProperty_ClientDataFormat, sizeof (AudioStreamBasicDescription), &audioFormat);
    
    int numSamples = 1024; //How many samples to read in at a time
    UInt32 outputBufferSize = numSamples * audioFormat.mBytesPerFrame;

    // So the lvalue of outputBuffer is the memory location where we have reserved space
//    UInt16 *outputBuffer = (NSUInteger *)malloc(sizeof(UInt16 *) * outputBufferSize);
    void *outputBuffer = malloc(sizeof(SInt16 *) * outputBufferSize);

    AudioBufferList *convertedData = (AudioBufferList*)malloc(sizeof(AudioBufferList));;

    convertedData->mNumberBuffers = 1;    // Set this to 1 for mono
    convertedData->mBuffers[0].mNumberChannels = audioFormat.mChannelsPerFrame;  //also = 1
    convertedData->mBuffers[0].mDataByteSize = outputBufferSize;
    convertedData->mBuffers[0].mData = outputBuffer;

    UInt32 frameCount = numSamples;
    SInt16 *samplesAsCArray;
    UInt64 indexCount = 0;

    while (frameCount > 0) {
        ExtAudioFileRead(fileRef, &frameCount, convertedData);
        if (frameCount > 0)  {
            samplesAsCArray = (SInt16 *)convertedData->mBuffers[0].mData; // CAST YOUR mData INTO FLOAT

           for (int i =0; i< frameCount; i++) { //YOU CAN PUT numSamples INTEAD OF 1024
               printf("\n%llu\t%.4f", indexCount, samplesAsCArray[i]*1.0f/32768);
               indexCount ++;
            }
        }
    }
    
    // Free memory and turn off audio
    ExtAudioFileDispose(fileRef);
    free(convertedData->mBuffers[0].mData);
    free(convertedData);
}

@end
