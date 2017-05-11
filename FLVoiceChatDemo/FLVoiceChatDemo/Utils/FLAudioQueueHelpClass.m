//
//  AudioQueueHelpClass.m
//  FLVoiceChatDemo
//
//  Created by Fan Lv on 2017/5/11.
//  Copyright © 2017年 Fanlv. All rights reserved.
//

#import "FLAudioQueueHelpClass.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#import "RecordAmrCode.h"


/**
 *  缓存区的个数，一般3个
 */
#define kNumberAudioQueueBuffers 3

/**
 *  采样率，要转码为amr的话必须为8000
 */
#define kDefaultSampleRate 8000

#define kDefaultInputBufferSize 8000

#define kDefaultOutputBufferSize 8000


@interface FLAudioQueueHelpClass()
{
    AudioQueueBufferRef     _inputBuffers[kNumberAudioQueueBuffers];
    AudioQueueBufferRef     _outputBuffers[kNumberAudioQueueBuffers];
    
//    AudioConverterRef m_converter;
    
    AudioQueueRef                   _inputQueue;
    AudioQueueRef                   _outputQueue;


}
@property (assign, nonatomic) AudioQueueRef inputQueue;
@property (assign, nonatomic) AudioQueueRef outputQueue;
@property (strong, nonatomic) NSMutableArray *receiveData;//接收数据的数组

@property (strong, nonatomic) NSLock *synclockIn;
@property (strong, nonatomic) NSLock *synclockOut;

@property (assign, nonatomic) BOOL isSettingSpeaker;


@end


@implementation FLAudioQueueHelpClass



+ (instancetype)shareInstance
{
    static FLAudioQueueHelpClass *audioQueueHelpClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioQueueHelpClass = [[FLAudioQueueHelpClass alloc] init];
    });
    return audioQueueHelpClass;
}


- (id)init
{
    self = [super init];
    if (self) {
        _receiveData = [[NSMutableArray alloc] init];
        _synclockIn = [[NSLock alloc] init];
        _synclockOut = [[NSLock alloc] init];
        _isSettingSpeaker = NO;
        
        [self initAVAudioSession];
        [self initPlayAudioQueue];
        [self initRecordAudioQueue];
    }
    return self;
}






#pragma mark - 设置音频输入输出参数

#pragma mark  initAVAudioSession


- (void)initAVAudioSession
{
    NSError *error = nil;
    [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
    //设置audioSession格式 录音播放模式
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    
}


#pragma mark  初始化录音的队列
- (void)initRecordAudioQueue
{
    
    //设置录音的参数
    AudioStreamBasicDescription audioFormat =[self setupAudioFormat:kAudioFormatLinearPCM SampleRate:kDefaultSampleRate];
    
    //创建一个录制音频队列
    AudioQueueNewInput (&audioFormat,GenericInputCallback,(__bridge void *)self,NULL,NULL,0,&_inputQueue);
    
    //创建录制音频队列缓冲区
    for (int i = 0; i < kNumberAudioQueueBuffers; i++) {
        AudioQueueAllocateBuffer (_inputQueue,kDefaultInputBufferSize,&_inputBuffers[i]);
        AudioQueueEnqueueBuffer (_inputQueue,(_inputBuffers[i]),0,NULL);
    }
    
    //-----设置音量
    Float32 gain = 1.0;                                       // 1
    // Optionally, allow user to override gain setting here 设置音量
    AudioQueueSetParameter (_outputQueue,kAudioQueueParam_Volume,gain);
    
}

// 设置录音格式
- (AudioStreamBasicDescription)setupAudioFormat:(UInt32) inFormatID SampleRate:(int)sampeleRate
{
    AudioStreamBasicDescription audioFormat;
    //重置下
    memset(&audioFormat, 0, sizeof(audioFormat));
    
    
    //    int tmp = [[AVAudioSession sharedInstance] sampleRate];
    //设置采样率，这里先获取系统默认的测试下 //TODO:
    //采样率的意思是每秒需要采集的帧数
    audioFormat.mSampleRate = sampeleRate;
    
    //    NSInteger inputNumberOfChannels = [[AVAudioSession sharedInstance] inputNumberOfChannels];
    //设置通道数,这里先使用系统的测试下 //TODO:
    audioFormat.mChannelsPerFrame = 2;//inputNumberOfChannels;
    
    //设置format，怎么称呼不知道。
    audioFormat.mFormatID = inFormatID;
    
    if (inFormatID == kAudioFormatLinearPCM){
        audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        //每个通道里，一帧采集的bit数目
        audioFormat.mBitsPerChannel = 16;
        //结果分析: 8bit为1byte，即为1个通道里1帧需要采集2byte数据，再*通道数，即为所有通道采集的byte数目。
        //所以这里结果赋值给每帧需要采集的byte数目，然后这里的packet也等于一帧的数据。
        audioFormat.mBytesPerPacket = audioFormat.mBytesPerFrame = (audioFormat.mBitsPerChannel / 8) * audioFormat.mChannelsPerFrame;
        audioFormat.mFramesPerPacket = 1;
    }
    
    return audioFormat;
    
}


#pragma mark - 初始化播放队列

- (void)initPlayAudioQueue
{
    
    //设置录音的参数
    AudioStreamBasicDescription audioFormat =[self setupAudioFormat:kAudioFormatLinearPCM SampleRate:kDefaultSampleRate];
    //创建一个输出队列
    OSStatus status = AudioQueueNewOutput(&audioFormat, GenericOutputCallback, (__bridge void *) self, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0,&_outputQueue);
    NSLog(@"status ：%d",status);
    
    //创建并分配缓冲区空间3个缓冲区
    for (int i=0; i < kNumberAudioQueueBuffers; ++i) {
        AudioQueueAllocateBuffer(_outputQueue, kDefaultOutputBufferSize, &_outputBuffers[i]);
        
        makeSilent(_outputBuffers[i]);  //改变数据
        // 给输出队列完成配置
        AudioQueueEnqueueBuffer(_outputQueue,_outputBuffers[i],0,NULL);
    }
}


//把缓冲区置空
void makeSilent(AudioQueueBufferRef buffer)
{
    for (int i=0; i < buffer->mAudioDataBytesCapacity; i++) {
        buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
        UInt8 * samples = (UInt8 *) buffer->mAudioData;
        samples[i]=0;
    }
}


#pragma mark - 麦克风音频数据处理 PCM->ACC

- (void)handlePCMdata
{
    
}



#pragma mark - 音频输入输出回调

//录音回调
void GenericInputCallback (
                           void                                *inUserData,
                           AudioQueueRef                       inAQ,
                           AudioQueueBufferRef                 inBuffer,
                           const AudioTimeStamp                *inStartTime,
                           UInt32                              inNumberPackets,
                           const AudioStreamPacketDescription  *inPacketDescs
                           )
{
    
    FLAudioQueueHelpClass *aq = [FLAudioQueueHelpClass shareInstance];
//    [aq.synclockOut lock];
    if (!aq.isSettingSpeaker)
    {

        if (inNumberPackets > 0) {
            NSData *pcmData = [[NSData alloc] initWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
            //pcm数据不为空时，编码为amr格式
            if (pcmData && pcmData.length > 0) {
                NSData *amrData = [RecordAmrCode encodePCMDataToAMRData:pcmData];
                if ([FLAudioQueueHelpClass shareInstance].recordWithData) {
                    [FLAudioQueueHelpClass shareInstance].recordWithData(amrData);
                }
            }
        }
    }
    AudioQueueEnqueueBuffer (inAQ,inBuffer,0,NULL);
//    [aq.synclockOut unlock];
}






// 输出回调、播放回调
void GenericOutputCallback (
                            void                 *inUserData,
                            AudioQueueRef        inAQ,
                            AudioQueueBufferRef  inBuffer
                            )
{

    NSData *pcmData = nil;
    
    FLAudioQueueHelpClass *aq = [FLAudioQueueHelpClass shareInstance];
    
    if([aq.receiveData count] >0 && !aq.isSettingSpeaker)
    {
        NSData *amrData = [aq.receiveData objectAtIndex:0];
        pcmData =  [RecordAmrCode decodeAMRDataToPCMData:[amrData copy]];
        if (pcmData && pcmData.length < 10000) {
            memcpy(inBuffer->mAudioData, pcmData.bytes, pcmData.length);
            inBuffer->mAudioDataByteSize = (UInt32)pcmData.length;
            inBuffer->mPacketDescriptionCount = 0;
        }
        @synchronized (aq.receiveData) {
            [aq.receiveData removeObjectAtIndex:0];
        }
    }
    else
    {
        makeSilent(inBuffer);
    }
    
    AudioQueueEnqueueBuffer([FLAudioQueueHelpClass shareInstance].outputQueue,inBuffer,0,NULL);
    
    
    //    [synclockIn unlock];
    
}



#pragma mark - Action



- (void)startRecordQueue
{
    //开启录制队列
    AudioQueueStart(_inputQueue, NULL);

}

- (void)starPlayQueue
{
    [_receiveData removeAllObjects];
    //开启播放队列
    AudioQueueStart(_outputQueue,NULL);
}


/**
 开始记录和播放队列
 */
- (void)startRecordAndPlayQueue
{
    [self startRecordQueue];
    [self starPlayQueue];
}

/**
 停止播放和录音
 */
- (void)stopRecordAndPlayQueue
{
    [_synclockOut lock];
    AudioQueueDispose(_outputQueue, YES);
    [_synclockOut unlock];
    
    [_synclockIn lock];
    AudioQueueDispose(_inputQueue, YES);
    [_synclockIn unlock];
    
}



/**
 播放音频数据
 
 @param data 音频流数据
 */
- (void)playAudioData:(NSData *)data
{
    @synchronized (_receiveData) {
        [_receiveData addObject:data];
    }
}

/**
 设置是否扬声器播放
 */
- (void)setSpeak:(BOOL)on
{
    
    [_synclockOut lock];
    
    _isSettingSpeaker = YES;
    //        AudioQueuePause(_outputQueue);
    //        AudioQueuePause(_inputQueue);
    //        AudioQueueFlush(_inputQueue);
    //        AudioQueueFlush(_outputQueue);
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
    
    sleep(.6);
    _isSettingSpeaker = NO;
    
    [_synclockOut unlock];
    

}


#pragma mark - 处理近距离监听触发事件
/**
 传感器开关是不是打开，打开以后靠近就开启听筒模式
 
 @param enable 是否开启
 */
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


@end





















