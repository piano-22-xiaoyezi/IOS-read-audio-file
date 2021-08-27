//
//  batchData.m
//  audio-rt-sdk
//
//  Created by edz on 2021/7/27.
//  Copyright © 2021 Jim. All rights reserved.
//

#import "batchData.h"
#import <AudioToolbox/AudioToolbox.h>

#import "TFWorker.h"
#import "TFRtWorker.h"
#import "TFFullWorker.h"
#import "TfSpec.h"
#import "AudioRTManager.h"

static const int SPEC_DEFAULT_COL_NUM = 8;
static const int SPEC_DEFAULT_COL_LEN = 229;
static const int SPEC_OUT_DEFAULT_LEN = SPEC_DEFAULT_COL_NUM * SPEC_DEFAULT_COL_LEN;
static const double perDataTimeStamp = 1.f / 16000.f;
static const int numSamples = 512; //How many samples to read in at a time

@interface BatchData(){
    // 全功能处理
    TFFullWorker *_fullWorker;

    // 当前录音分片的时间戳
    double _totalAudioLen;
    UInt64 _totalSpecLen;
    NSLock *_tsLock;
    long _pendingNum;
    BOOL _saveTempAudioData;
    BOOL _enableAec;
    
}

@property (atomic, strong)      TFMidiTool          *midiTool;
@property (atomic, strong)      NSMutableArray      *timestampArr;
@property (atomic, strong)      NSString      *wavPath;

@end


@implementation BatchData

+ (id) getInstance {
    static BatchData *batchData;
    static dispatch_once_t oneToken;
    dispatch_once(&oneToken, ^{
        batchData = [[BatchData alloc] init];
    });
    return batchData;
}

- (void) startBatchData {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *audioaPath = [[paths objectAtIndex:0]stringByAppendingPathComponent:@"testData"];
    NSArray *subpaths = [fileManager subpathsAtPath:audioaPath];
    [self initWithConfig];  // init
    for(int i=0; i<subpaths.count; i++) {
        NSLog(@"%@", subpaths[i]);
        @autoreleasepool {
            if (![subpaths[i] hasSuffix:@".wav"]) continue;
            _wavPath = [audioaPath stringByAppendingPathComponent:subpaths[i]];
            NSLog(@"%@", _wavPath);
            if ([fileManager fileExistsAtPath:[self getJsonPath]]) {
                NSLog(@"file exist, continue");
//                [fileManager removeItemAtPath:[self getJsonPath] error:nil];  // 删除存在文件
                continue;
            }
            [self reset];  // reset
            [self singleAudioParser:_wavPath];
        }
        NSLog(@"end");
        [fileManager moveItemAtPath:[self getTmpJsonPath] toPath:[self getJsonPath] error:nil];
    }
}

- (NSString *) getTmpJsonPath {
    NSString *jsonPath = [_wavPath stringByReplacingOccurrencesOfString:@".wav" withString:@".json.tmp"];
    return jsonPath;
}

- (NSString *) getJsonPath {
    NSString *jsonPath = [_wavPath stringByReplacingOccurrencesOfString:@".wav" withString:@".json"];
    return jsonPath;
}

- (void) singleAudioParser:(NSString *)audioaPath {
//    const char *cString = [audioaPath cStringUsingEncoding:NSASCIIStringEncoding];
//    if (!cString) {
//        NSLog(@"文件名有中文，停止交易！！！");
//        return;
//    }
//    CFStringRef str = CFStringCreateWithCString(NULL, cString,  kCFStringEncodingMacRoman);
//    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, str, kCFURLPOSIXPathStyle, false);
    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)audioaPath, kCFURLPOSIXPathStyle, false);

    ExtAudioFileRef fileRef;
    ExtAudioFileOpenURL(inputFileURL, &fileRef);
    
    AudioStreamBasicDescription audioFormat;

    audioFormat.mSampleRate = 16000; // 采样率 ：Hz
    audioFormat.mFormatID = kAudioFormatLinearPCM; // 采样数据的类型，PCM,AAC等
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeEndian;
    audioFormat.mFramesPerPacket = 1;  // 一个数据包中的帧数，每个packet的帧数。如果是未压缩的音频数据，值是1。动态帧率格式，这个值是一个较大的固定数字，比如说AAC的1024。如果是动态大小帧数（比如Ogg格式）设置为0。
    audioFormat.mChannelsPerFrame = 1; // 每一帧数据中的通道数，单声道为1，立体声为2
    audioFormat.mBitsPerChannel = 16; // 每个通道中的位数，1byte = 8bit
    audioFormat.mBytesPerFrame = audioFormat.mChannelsPerFrame * 2;; // 每一帧中的字节数
    audioFormat.mBytesPerPacket = audioFormat.mFramesPerPacket * audioFormat.mBytesPerFrame;; // 一个数据包中的字节数

    // 3) Apply audio format to the Extended Audio File
    ExtAudioFileSetProperty(fileRef, kExtAudioFileProperty_ClientDataFormat, sizeof (AudioStreamBasicDescription), &audioFormat);
    UInt32 outputBufferSize = numSamples * audioFormat.mBytesPerFrame;

    // So the lvalue of outputBuffer is the memory location where we have reserved space
    void *outputBuffer = malloc(sizeof(SInt16 *) * outputBufferSize);

    AudioBufferList *convertedData = (AudioBufferList*)malloc(sizeof(AudioBufferList));

    convertedData->mNumberBuffers = 1;    // Set this to 1 for mono
    convertedData->mBuffers[0].mNumberChannels = audioFormat.mChannelsPerFrame;  //also = 1
    convertedData->mBuffers[0].mDataByteSize = outputBufferSize;
    convertedData->mBuffers[0].mData = outputBuffer;

    UInt32 frameCount = numSamples;
    SInt16 *samplesAsCArray;

    while (frameCount > 0) {
        ExtAudioFileRead(fileRef, &frameCount, convertedData);
        if (frameCount > 0)  {
            samplesAsCArray = (SInt16 *)convertedData->mBuffers[0].mData; // CAST YOUR mData INTO FLOAT
            float *testData = malloc(sizeof(float) * frameCount);
            for (int i =0; i< frameCount; i++) { //YOU CAN PUT numSamples INTEAD OF 1024
                testData[i] = samplesAsCArray[i]*1.f/32767.f;
            }
            [self processAudio:testData length:frameCount];
            free(testData);
        }
    }
    
    // Free memory and turn off audio
    ExtAudioFileDispose(fileRef);
    free(convertedData->mBuffers[0].mData);
    free(convertedData);
}

// deal audio data

- (void) initWithConfig {
    [self setupTFMidiTool];
    NSDictionary *fullModelInfo = [self getDefaultConfig];
    _fullWorker = [[TFFullWorker alloc] initWithConfig:fullModelInfo andMidiTool:_midiTool];
}

- (void) reset {
    reset();
    _enableAec = YES;
    _totalAudioLen = 0;
    _totalSpecLen = 0;
    [_fullWorker reset:_enableAec];
    _timestampArr = [[NSMutableArray alloc] init];
}

- (void) setupTFMidiTool {
    self.midiTool = [[TFMidiTool alloc] init];
}

- (NSDictionary *) getDefaultConfig {
    NSMutableDictionary *modelInfo = [NSMutableDictionary dictionary];
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"converted_model" ofType:@"tflite"];

    NSMutableDictionary *fullModelPolicy = [NSMutableDictionary dictionary];
    [fullModelPolicy setValue:@(229) forKey:@"spec_col_len"];
    [fullModelPolicy setValue:@(3) forKey:@"spec_left_padding_num"];
    [fullModelPolicy setValue:@(3) forKey:@"spec_right_padding_num"];
    [fullModelPolicy setValue:@(8) forKey:@"spec_col_num"];

    [modelInfo setObject:fullModelPolicy forKey:@"policy"];
    [modelInfo setObject:modelPath forKey:@"path"];

    return modelInfo;
}

- (void) processAudio:(float *)audioData length:(UInt32 ) len {
    int pos[] = {0};
    float specOut[SPEC_OUT_DEFAULT_LEN] = {0};
    int specLen = 0;
    _totalAudioLen += len;
    NSMutableDictionary *ele = [NSMutableDictionary dictionary];
    [ele setObject:[NSNumber numberWithDouble:perDataTimeStamp * _totalAudioLen * 1000] forKey:@"timestamp"];
    [ele setObject:[NSNumber numberWithDouble:_totalAudioLen] forKey:@"totalLen"];
    
    if (_timestampArr.count > TIMESTAMP_COUNT) {
        [_timestampArr removeObjectAtIndex:0];
    }
    [_timestampArr addObject:ele];
    
    // check wav data
//    for (int i=0; i<len; i++) {
//        printf("%.0f\t%.4f\n", _totalAudioLen-len+i, audioData[i]);
//    }
   
    if (_totalSpecLen <= 0) {  // send zero data
        int num = 2048;
        float *tmpdata = malloc(sizeof(float) * num);
        for (int i=0; i<num; i++) {
            tmpdata[i] = 0;
        }
        specLen = getSpec(tmpdata, num, specOut, SPEC_OUT_DEFAULT_LEN, pos);
        _totalSpecLen += specLen;
    } else {
        specLen = getSpec(audioData, len, specOut, SPEC_OUT_DEFAULT_LEN, pos);
        _totalSpecLen += specLen;
        
        //  check spec data
//        for (int i=0; i<specLen; i++){
////            if (specOut[i] < -2.f) continue;
//            printf("%llu \t %.4f \t %u\n", _totalSpecLen-specLen+i, specOut[i], specLen);
//        }

        // TODO: start worker according to the different scenes
        [_fullWorker processAudio:_timestampArr andData:specOut andLen:specLen * 4];
    }
}

@end
