//
//  FLAudioUnitHelpClass.m
//  FLVoiceChatDemo
//
//  Created by Fan Lv on 2017/5/16.
//  Copyright © 2017年 Fanlv. All rights reserved.
//

#import "FLAudioUnitHelpClass.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "RecordAmrCode.h"



#include <pthread.h>
//#import "BNRAudioData.h"
//#import <AudioUnit/AudioUnit.h>


#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "RecordAmrCode.h"



#include <pthread.h>
#import <AudioUnit/AudioUnit.h>

// *  缓存区的个数，一般3个
#define kNumberAudioQueueBuffers 3


/**
 *  采样率，要转码为amr的话必须为8000
 需要注意，AAC并不是随便的码率都可以支持。比如如果PCM采样率是44100KHz，那么码率可以设置64000bps，如果是16K，可以设置为32000bps。
 
 */
#define kDefaultSampleRate 44100//16000



#define kDefaultSamplebitRate 64000//32000





#define handleError(error)  if(error){ NSLog(@"%@",error); }


#define kOutoutBus 0
#define kInputBus  1
#define kRecordDataLen  (1024*20)




typedef struct {
    NSInteger   front;
    NSInteger   rear;
    SInt16      recordArr[kRecordDataLen];
} RecordStruct;


static pthread_mutex_t  recordLock;
static pthread_cond_t   recordCond;

static pthread_mutex_t  playLock;




RecordStruct    recordStruct;



@interface FLAudioUnitHelpClass()
{
    AudioQueueBufferRef     _inputBuffers[kNumberAudioQueueBuffers];
    AudioQueueBufferRef     _outputBuffers[kNumberAudioQueueBuffers];
    

    
    
    AURenderCallbackStruct      _inputProc;

    AudioStreamBasicDescription     _pcmFormatDes;      ///< PCM format
    AudioStreamBasicDescription     _accFormatDes;      ///< ACC format
    AudioConverterRef               _encodeConvertRef;  ///PCM转ACC的编码器

    
    
    
}
@property (nonatomic,assign) AudioComponentInstance toneUnit;

@property (assign, nonatomic) AudioQueueRef outputQueue;
@property (strong, nonatomic) NSMutableArray *receiveData;//接收数据的数组
@property (strong, nonatomic) NSMutableData *sendBuffer;//接收数据的数组

@property (strong, nonatomic) NSLock *synclockOut;




@property (nonatomic,assign) BOOL startRecord;
@property (nonatomic,assign) BOOL startPlay;

@end


@implementation FLAudioUnitHelpClass



+ (instancetype)shareInstance
{
    static FLAudioUnitHelpClass *audioQueueHelpClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioQueueHelpClass = [[FLAudioUnitHelpClass alloc] init];
    });
    return audioQueueHelpClass;
}


- (id)init
{
    self = [super init];
    if (self) {
        _receiveData = [[NSMutableArray alloc] init];
        _synclockOut = [[NSLock alloc] init];
        _sendBuffer = [[NSMutableData alloc] init];
        
        int rc;
        rc = pthread_mutex_init(&recordLock,NULL);
        assert(rc == 0);
        rc = pthread_cond_init(&recordCond, NULL);
        assert(rc == 0);
        
        rc = pthread_mutex_init(&playLock,NULL);
        assert(rc == 0);
        
        memset(recordStruct.recordArr, 0, kRecordDataLen);
        recordStruct.front = recordStruct.rear = 0;

        
        [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];

        [self initAVAudioSession1];
        [self setupPCMAudioFormat1];
        [self setupACCAudioFormat1];
        [self makeEncodeAudioConverterSourceDes1:_pcmFormatDes targetDes:_accFormatDes];
        [self initRecordAudioUnit];

        
    }
    return self;
}




#pragma mark  initAVAudioSession


- (void)initAVAudioSession1
{
    //对AudioSession的一些设置
    NSError *error;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    handleError(error);
    //route变化监听(//添加通知，拔出耳机后暂停播放)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionRouteChangeHandle:) name:AVAudioSessionRouteChangeNotification object:session];
    
    [session setPreferredIOBufferDuration:0.005 error:&error];
    handleError(error);
    [session setPreferredSampleRate:kDefaultSampleRate error:&error];
    handleError(error);
    
    [session setActive:YES error:&error];
    handleError(error);
}



#pragma mark - 设置输入输出音频格式信息


// 设置录音格式
- (void)setupPCMAudioFormat1
{
    //重置下
    memset(&_pcmFormatDes, 0, sizeof(_pcmFormatDes));
    
    //    int tmp = [[AVAudioSession sharedInstance] sampleRate];
    //设置采样率，这里先获取系统默认的测试下 //TODO:
    //采样率的意思是每秒需要采集的帧数
    _pcmFormatDes.mSampleRate = kDefaultSampleRate;
    
    //设置通道数,这里先使用系统的测试下
    _pcmFormatDes.mChannelsPerFrame = kInputBus;
    
    //设置format，怎么称呼不知道。
    _pcmFormatDes.mFormatID = kAudioFormatLinearPCM;
    
    _pcmFormatDes.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    //每个通道里，一帧采集的bit数目
    _pcmFormatDes.mBitsPerChannel = 16;
    //结果分析: 8bit为1byte，即为1个通道里1帧需要采集2byte数据，再*通道数，即为所有通道采集的byte数目。
    //所以这里结果赋值给每帧需要采集的byte数目，然后这里的packet也等于一帧的数据。
    _pcmFormatDes.mBytesPerPacket = _pcmFormatDes.mBytesPerFrame = (_pcmFormatDes.mBitsPerChannel / 8) * _pcmFormatDes.mChannelsPerFrame;
    _pcmFormatDes.mFramesPerPacket = 1;// 用AudioQueue采集pcm需要这么设置
    _pcmFormatDes.mReserved           = 0;
    
}


- (void)setupACCAudioFormat1
{
    memset(&_accFormatDes, 0, sizeof(_accFormatDes));
    _accFormatDes.mFormatID                   = kAudioFormatMPEG4AAC;
    _accFormatDes.mSampleRate                 = kDefaultSampleRate;
    _accFormatDes.mFramesPerPacket            = 1024;
    //设置通道数,这里先使用系统的测试下
    _accFormatDes.mChannelsPerFrame = kInputBus;
    
    OSStatus status     = 0;
    UInt32 targetSize   = sizeof(_accFormatDes);
    status              = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &targetSize, &_accFormatDes);
}


#pragma mark - 生成编码器


/**
 生成编码器
 
 @param sourceDes 音频原格式 PCM
 @param targetDes 音频目标格式 ACC
 */
- (void)makeEncodeAudioConverterSourceDes1:(AudioStreamBasicDescription)sourceDes targetDes:(AudioStreamBasicDescription)targetDes
{
    
    // 此处目标格式其他参数均为默认，系统会自动计算，否则无法进入encodeConverterComplexInputDataProc回调
    
    OSStatus status     = 0;
    UInt32 targetSize   = sizeof(targetDes);
    status              = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &targetSize, &targetDes);
    
    
    
    // 选择软件编码
    AudioClassDescription audioClassDes;
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                        sizeof(targetDes.mFormatID),
                                        &targetDes.mFormatID,
                                        &targetSize);

    
    UInt32 numEncoders = targetSize/sizeof(AudioClassDescription);
    AudioClassDescription audioClassArr[numEncoders];
    AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                           sizeof(targetDes.mFormatID),
                           &targetDes.mFormatID,
                           &targetSize,
                           audioClassArr);

    
    for (int i = 0; i < numEncoders; i++) {
        if (audioClassArr[i].mSubType == kAudioFormatMPEG4AAC && audioClassArr[i].mManufacturer == kAppleSoftwareAudioCodecManufacturer) {
            memcpy(&audioClassDes, &audioClassArr[i], sizeof(AudioClassDescription));
            break;
        }
    }
    
    status          = AudioConverterNewSpecific(&sourceDes, &targetDes, 1,
                                                &audioClassDes, &_encodeConvertRef);
    
    targetSize      = sizeof(sourceDes);
    status          = AudioConverterGetProperty(_encodeConvertRef, kAudioConverterCurrentInputStreamDescription, &targetSize, &sourceDes);
    
    targetSize      = sizeof(targetDes);
    status          = AudioConverterGetProperty(_encodeConvertRef, kAudioConverterCurrentOutputStreamDescription, &targetSize, &targetDes);
    
    // 设置码率，需要和采样率对应
    UInt32 bitRate  = kDefaultSamplebitRate;
    targetSize      = sizeof(bitRate);
    status          = AudioConverterSetProperty(_encodeConvertRef,
                                                kAudioConverterEncodeBitRate,
                                                targetSize, &bitRate);
}

#pragma mark - 初始化播放队列

- (void)initPlayAudioQueue1
{
    //创建一个输出队列
    OSStatus status = AudioQueueNewOutput(&_accFormatDes, GenericOutputCallback12, (__bridge void *) self, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0,&_outputQueue);
    NSLog(@"status ：%d",status);
    
    //创建并分配缓冲区空间3个缓冲区
    for (int i=0; i < kNumberAudioQueueBuffers; ++i) {
        AudioQueueAllocateBuffer(_outputQueue, 1024*2, &_outputBuffers[i]);
        makeSilent1(_outputBuffers[i]);  //改变数据
        AudioStreamPacketDescription *paks = calloc(sizeof(AudioStreamPacketDescription), 1);
        paks[0].mStartOffset = 0;
        paks[0].mDataByteSize = 0;
        CheckError(AudioQueueEnqueueBuffer(_outputQueue, _outputBuffers[i],1, paks), "cant enqueue");
    }
    
    
    //-----设置音量
    Float32 gain = 1.0;                                       // 1
    // Optionally, allow user to override gain setting here 设置音量
    AudioQueueSetParameter (_outputQueue,kAudioQueueParam_Volume,gain);
}


#pragma mark - 初始化录音单元

- (void)initRecordAudioUnit
{
    
    _inputProc.inputProc = inputRenderTone;
    _inputProc.inputProcRefCon = (__bridge void *)(self);
    
    
    //    Obtain a RemoteIO unit instance
    AudioComponentDescription acd;
    acd.componentType = kAudioUnitType_Output;
    acd.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &acd);
    AudioComponentInstanceNew(inputComponent, &_toneUnit);
    
    
    UInt32 enable = 1;
    AudioUnitSetProperty(_toneUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input,
                         kInputBus,
                         &enable,
                         sizeof(enable));
    
    
    
    CheckError(AudioUnitSetProperty(_toneUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output, kInputBus,
                                    &_pcmFormatDes, sizeof(_pcmFormatDes)),
               "couldn't set the remote I/O unit's input client format");
    
    CheckError(AudioUnitSetProperty(_toneUnit,
                                    kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Output,
                                    kInputBus,
                                    &_inputProc, sizeof(_inputProc)),
               "couldnt set remote i/o render callback for input");
    
    
    CheckError(AudioUnitInitialize(_toneUnit),
               "couldn't initialize the remote I/O unit");
    //    CheckError(AudioOutputUnitStart(_toneUnit), "couldnt start audio unit");
    
    
    
    
    
    
    [self performSelectorInBackground:@selector(convertPCMToAAC1) withObject:nil];
    
}



#pragma mark - 语音队列播放回调

//把缓冲区置空
void makeSilent1(AudioQueueBufferRef buffer)
{
    for (int i=0; i < buffer->mAudioDataBytesCapacity; i++) {
        buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
        UInt8 * samples = (UInt8 *) buffer->mAudioData;
        samples[i]=0;
    }
}


// 输出回调、播放回调
void GenericOutputCallback12 (void                 *inUserData,
                              AudioQueueRef        inAQ,
                              AudioQueueBufferRef  buffer)
{
    
    
    FLAudioUnitHelpClass *aq = [FLAudioUnitHelpClass shareInstance];
    [aq.synclockOut lock];
    
    BOOL  couldSignal = NO;
    static int lastIndex = 0;
    static int packageCounte = 3;
    
    if (aq.receiveData.count > packageCounte) {
        lastIndex = 0;
        couldSignal = YES;
    }
    if (couldSignal) {
        @autoreleasepool {
            NSMutableData *data = [[NSMutableData alloc] init];
            AudioStreamPacketDescription *paks = calloc(sizeof(AudioStreamPacketDescription), packageCounte);
            for (int i = 0; i < packageCounte ; i++) {
                NSData *audio = [aq.receiveData firstObject];
                [data appendData:audio];
                paks[i].mStartOffset = lastIndex;
                paks[i].mDataByteSize = (UInt32)[audio length];
                lastIndex += [audio length];
                
                pthread_mutex_lock(&playLock);
                [aq.receiveData removeObjectAtIndex:0];
                pthread_mutex_unlock(&playLock);
            }
            memcpy(buffer->mAudioData,[data bytes] , [data length]);
            buffer->mAudioDataByteSize = (UInt32)[data length];
            
            CheckError(AudioQueueEnqueueBuffer(aq.outputQueue, buffer, packageCounte, paks), "cant enqueue");
            free(paks);
        }
    }
    else{
//        AudioQueuePause(aq.outputQueue);
        
        NSLog(@"makeSilent");
        makeSilent1(buffer);
        AudioStreamPacketDescription *paks = calloc(sizeof(AudioStreamPacketDescription), 1);
        paks[0].mStartOffset = 0;
        paks[0].mDataByteSize = 0;
        CheckError(AudioQueueEnqueueBuffer(aq.outputQueue, buffer,1, paks), "cant enqueue");
    }
    [aq.synclockOut unlock];
    
    
}


#pragma mark - 测试音频录音




-(void)audioSessionRouteChangeHandle:(NSNotification *)noti
{
    //    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    //    if (self.startRecord) {
    //        CheckError(AudioOutputUnitStart(_toneUnit), "couldnt start audio unit");
    //    }
}









//录音的队列
static OSStatus inputRenderTone(
                                void *inRefCon,
                                AudioUnitRenderActionFlags 	*ioActionFlags,
                                const AudioTimeStamp 		*inTimeStamp,
                                UInt32 						inBusNumber,
                                UInt32 						inNumberFrames,
                                AudioBufferList 			*ioData)

{
    
    FLAudioUnitHelpClass *aq = [FLAudioUnitHelpClass shareInstance];
      /*
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = NULL;
    bufferList.mBuffers[0].mDataByteSize = 0;
    OSStatus status = AudioUnitRender(aq.toneUnit,
                                      ioActionFlags,
                                      inTimeStamp,
                                      kInputBus,
                                      inNumberFrames,
                                      &bufferList);
    
    
  
    NSInteger lastTimeRear = recordStruct.rear;
    for (int i = 0; i < inNumberFrames; i++) {
        SInt16 data = ((SInt16 *)bufferList.mBuffers[0].mData)[i];
        recordStruct.recordArr[recordStruct.rear] = data;
        recordStruct.rear = (recordStruct.rear+1)%kRecordDataLen;
    }
    if ((lastTimeRear/1024 + 1) == (recordStruct.rear/1024)) {
        pthread_cond_signal(&recordCond);
    }
    
    */
    
    
    
    AudioBuffer buffer;
    buffer.mData = NULL;
    buffer.mDataByteSize = 0;
    buffer.mNumberChannels = 1;
    
    AudioBufferList buffers;
    buffers.mNumberBuffers = 1;
    buffers.mBuffers[0] = buffer;
    
    OSStatus status = AudioUnitRender(aq.toneUnit,
                                      ioActionFlags,
                                      inTimeStamp,
                                      inBusNumber,
                                      inNumberFrames,
                                      &buffers);
    
    
    
    if (!status) {
        
        
        pthread_mutex_lock(&recordLock);
        
        int packageCountBuf = 2048;

        
        if ([aq.sendBuffer length] > packageCountBuf) {
            

            NSData *data = [aq.sendBuffer subdataWithRange:NSMakeRange(0, packageCountBuf)];
            AudioBufferList *bufferList = convertPCMBufferListToAAC(data);
            NSData *accData = [[NSData alloc] initWithBytes:bufferList->mBuffers[0].mData length:bufferList->mBuffers[0].mDataByteSize];
            if([accData length] > 0)
            {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    [FLAudioUnitHelpClass shareInstance].recordWithData(accData);
                });
                NSLog(@"%@: send data %lu",[[UIDevice currentDevice] name] , [accData length]);
            }

            
            // free memory
            free(bufferList->mBuffers[0].mData);
            free(bufferList);

//            //清空数据
//            [aq.sendBuffer resetBytesInRange:NSMakeRange(0, aq.sendBuffer.length)];
//            [aq.sendBuffer setLength:0];
            
            //删除数据
            [aq.sendBuffer replaceBytesInRange:NSMakeRange(0, packageCountBuf) withBytes:NULL length:0];//删除索引0到索引50的数据


            
            
        }else{

            [aq.sendBuffer appendBytes:buffers.mBuffers[0].mData length:buffers.mBuffers[0].mDataByteSize];

        }
        

        pthread_mutex_unlock(&recordLock);

        
        


    }
     
     
    
    return status;
}



// PCM -> AAC
AudioBufferList* convertPCMBufferListToAAC (NSData *data) {
    
    FLAudioUnitHelpClass *aq = [FLAudioUnitHelpClass shareInstance];
    UInt32   maxPacketSize    = 0;
    UInt32   size             = sizeof(maxPacketSize);
    OSStatus status;
    
    status = AudioConverterGetProperty(aq->_encodeConvertRef,
                                       kAudioConverterPropertyMaximumOutputPacketSize,
                                       &size,
                                       &maxPacketSize);
    AudioBufferList *outBufferList             = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    outBufferList->mNumberBuffers              = 1;
    outBufferList->mBuffers[0].mNumberChannels = 1;
    outBufferList->mBuffers[0].mData           = malloc(maxPacketSize);
    outBufferList->mBuffers[0].mDataByteSize   = (UInt32)[data length];
    
    AudioStreamPacketDescription outputPacketDescriptions;
    
    UInt32 inNumPackets = 1;
    
    // inNumPackets设置为1表示编码产生1帧数据即返回
    status = AudioConverterFillComplexBuffer(aq->_encodeConvertRef,
                                             encodeConverterComplexInputDataProc2,
                                             &data,
                                             &inNumPackets,
                                             outBufferList,
                                             &outputPacketDescriptions);
    return outBufferList;
}





-(void)convertPCMToAAC1{
    return;
    UInt32 maxPacketSize = 0;
    UInt32 size = sizeof(maxPacketSize);
    CheckError(AudioConverterGetProperty(_encodeConvertRef,
                                         kAudioConverterPropertyMaximumOutputPacketSize,
                                         &size,
                                         &maxPacketSize),
               "cant get max size of packet");
    
    AudioBufferList *bufferList = malloc(sizeof(AudioBufferList));
    bufferList->mNumberBuffers = 1;
    bufferList->mBuffers[0].mNumberChannels = 1;
    bufferList->mBuffers[0].mData = malloc(maxPacketSize);
    bufferList->mBuffers[0].mDataByteSize = maxPacketSize;
    
    for (; ; )
    {
        @autoreleasepool {
            
            
            pthread_mutex_lock(&recordLock);
            while (ABS(recordStruct.rear - recordStruct.front) < 1024 ) {
                pthread_cond_wait(&recordCond, &recordLock);
            }
            pthread_mutex_unlock(&recordLock);
            
            SInt16 *readyData = (SInt16 *)calloc(1024, sizeof(SInt16));
            memcpy(readyData, &recordStruct.recordArr[recordStruct.front], 1024*sizeof(SInt16));
            recordStruct.front = (recordStruct.front+1024)%kRecordDataLen;
            UInt32 packetSize = 1;
            bufferList->mBuffers[0].mDataByteSize = maxPacketSize;
            CheckError(AudioConverterFillComplexBuffer(_encodeConvertRef,
                                                       encodeConverterComplexInputDataProc,
                                                       readyData,
                                                       &packetSize,
                                                       bufferList,
                                                       NULL),
                       "cant set AudioConverterFillComplexBuffer");
            free(readyData);
            
            NSMutableData *fullData = [NSMutableData dataWithBytes:bufferList->mBuffers[0].mData length:bufferList->mBuffers[0].mDataByteSize];
            
            if ([FLAudioUnitHelpClass shareInstance].recordWithData) {
                [FLAudioUnitHelpClass shareInstance].recordWithData(fullData);
            }
            NSLog(@"%@: send  data %lu",[[UIDevice currentDevice] name] , [fullData length]);

        }
    }
}

OSStatus encodeConverterComplexInputDataProc(AudioConverterRef inAudioConverter,
                                             UInt32 *ioNumberDataPackets,
                                             AudioBufferList *ioData,
                                             AudioStreamPacketDescription **outDataPacketDescription,
                                             void *inUserData)
{
    ioData->mBuffers[0].mData = inUserData;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mDataByteSize = 1024*2;
    *ioNumberDataPackets = 1024;
    return 0;
}



OSStatus encodeConverterComplexInputDataProc2(AudioConverterRef              inAudioConverter,
                                              UInt32                         *ioNumberDataPackets,
                                              AudioBufferList                *ioData,
                                              AudioStreamPacketDescription   **outDataPacketDescription,
                                              void                           *inUserData) {
    
    
    FLAudioUnitHelpClass *aq = [FLAudioUnitHelpClass shareInstance];
    
    ioData->mBuffers[0].mData           = inUserData;
    ioData->mBuffers[0].mNumberChannels = aq->_accFormatDes.mChannelsPerFrame;
    ioData->mBuffers[0].mDataByteSize   = 1024*2; // 2 为dataFormat.mBytesPerFrame 每一帧的比特数
    
    return 0;
}






#pragma mark - Action



- (void)startRecordQueue:(BOOL)startRecord
{
    _startRecord = startRecord;
    if (_startRecord) {
        CheckError(AudioOutputUnitStart(_toneUnit), "couldnt start audio unit");
    }else{
        CheckError(AudioOutputUnitStop(_toneUnit), "couldnt stop audio unit");
    }
}

- (void)starPlayQueue:(BOOL)startPlay
{
    _startPlay = startPlay;
    if (_startPlay) {
        pthread_mutex_lock(&playLock);
        [_receiveData removeAllObjects];
        [self initPlayAudioQueue1];
//        AudioQueueStart(_outputQueue,NULL);//开启播放队列
        pthread_mutex_unlock(&playLock);

    }else{
//        [_synclockOut lock];
        AudioQueueDispose(_outputQueue, YES);
//        [_synclockOut unlock];
    }
    
}



- (void)startRecordAndPlayQueue
{
    [self startRecordQueue:YES];
    [self starPlayQueue:YES];
}


- (void)stopRecordAndPlayQueue
{
    [self startRecordQueue:NO];
    [self starPlayQueue:NO];
}





- (void)playAudioData:(NSData *)data
{
    
//    NSLog(@"%@: rece data %lu",[[UIDevice currentDevice] name] , [data length]);
    

    if (_startPlay == NO)
        return;
    
    pthread_mutex_lock(&playLock);
    [_receiveData addObject:data];
    pthread_mutex_unlock(&playLock);
    //------------------------
    
    [_synclockOut lock];
    if ([_receiveData count] < 8) {//没有数据包的时候，要暂停队列，不然会出现播放一段时间后没有声音的情况。
        AudioQueuePause(_outputQueue);
    }else{
        AudioQueueStart(_outputQueue,NULL);//开启播放队列
    }
    [_synclockOut unlock];

    
    
    
    
}


- (void)setSpeak:(BOOL)on
{
    [_synclockOut lock];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    if (on)
    {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
    }
    else
    {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error];
    }
    [_synclockOut unlock];
}




- (void)setProximityMonitoringEnabled:(BOOL)enable
{
    [[UIDevice currentDevice] setProximityMonitoringEnabled:enable];
    if (enable) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sensorStateChange:) name:UIDeviceProximityStateDidChangeNotification object:nil];
    }else{
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceProximityStateDidChangeNotification object:nil];
    }
}


-(void)sensorStateChange:(NSNotificationCenter *)notification;
{
    [_synclockOut lock];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    if ([[UIDevice currentDevice] proximityState] == YES)//黑屏
    {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
    }
    else
    {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error];
    }
    [_synclockOut unlock];
    
}



#pragma mark - 打印logo的基本函数



static void CheckError(OSStatus error,const char *operaton){
    if (error==noErr) {
        return;
    }
    char errorString[20]={};
    *(UInt32 *)(errorString+1)=CFSwapInt32HostToBig(error);
    if (isprint(errorString[1])&&isprint(errorString[2])&&isprint(errorString[3])&&isprint(errorString[4])) {
        errorString[0]=errorString[5]='\'';
        errorString[6]='\0';
    }else{
        sprintf(errorString, "%d",(int)error);
    }
    fprintf(stderr, "Error:%s (%s)\n",operaton,errorString);
//    exit(1);
}


#pragma mark - Rotate
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    UIInterfaceOrientation orientation = [self preferredInterfaceOrientationForPresentation];
    if ((orientation != UIInterfaceOrientationLandscapeLeft) && (orientation != UIInterfaceOrientationLandscapeRight)) {
        orientation = UIInterfaceOrientationLandscapeRight;
    }
    return orientation;
}


@end

