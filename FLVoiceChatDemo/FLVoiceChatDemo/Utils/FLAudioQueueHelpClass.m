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
//        [self initPlayAudioQueue];
//        [self initRecordAudioQueue];
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

//把缓冲区置空
void makeSilent(AudioQueueBufferRef buffer)
{
    for (int i=0; i < buffer->mAudioDataBytesCapacity; i++) {
        buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
        UInt8 * samples = (UInt8 *) buffer->mAudioData;
        samples[i]=0;
    }
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
    [self initRecordAudioQueue];
    //开启录制队列
    AudioQueueStart(_inputQueue, NULL);

}

- (void)starPlayQueue
{
    [_receiveData removeAllObjects];
    [self initPlayAudioQueue];
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
//    AudioQueueStop(_outputQueue, YES);
    [_synclockOut unlock];
    
    [_synclockIn lock];
    AudioQueueDispose(_inputQueue, YES);
//    AudioQueueStop(_inputQueue, YES);
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
    
//    sleep(.6);
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










/*
 开始播放
 OSStatus AudioQueueStart(AudioQueueRef inAQ,const AudioTimeStamp * inStartTime);
 第二个参数可以用来控制播放开始的时间，一般情况下直接开始播放传入NULL即可。


 2.解码数据
 OSStatus AudioQueuePrime(AudioQueueRef inAQ,
 UInt32 inNumberOfFramesToPrepare,
 UInt32 * outNumberOfFramesPrepared);
 这个方法并不常用，因为直接调用AudioQueueStart会自动开始解码（如果需要的话）。参数的作用是用来指定需要解码帧数和实际完成解码的帧数；

 3.暂停播放
 OSStatus AudioQueuePause(AudioQueueRef inAQ);
 需要注意的是这个方法一旦调用后播放就会立即暂停，这就意味着AudioQueueOutputCallback回调也会暂停，这时需要特别关注线程的调度以防止线程陷入无限等待。

 4.停止播放
 OSStatus AudioQueueStop(AudioQueueRef inAQ, Boolean inImmediate);
 第二个参数如果传入true的话会立即停止播放（同步），如果传入false的话AudioQueue会播放完已经Enqueue的所有buffer后再停止（异步）。使用时注意根据需要传入适合的参数。

 5.Flush
 OSStatus
 AudioQueueFlush(AudioQueueRef inAQ);
 调用后会播放完Enqueu的所有buffer后重置解码器状态，以防止当前的解码器状态影响到下一段音频的解码（比如切换播放的歌曲时）。如果和AudioQueueStop(AQ,false)一起使用并不会起效，因为Stop方法的false参数也会做同样的事情。
 
 6.重置
 OSStatus AudioQueueReset(AudioQueueRef inAQ);
 重置AudioQueue会清除所有已经Enqueue的buffer，并触发AudioQueueOutputCallback,调用AudioQueueStop方法时同样会触发该方法。这个方法的直接调用一般在seek时使用，用来清除残留的buffer（seek时还有一种做法是先AudioQueueStop，等seek完成后重新start）。
 
 7.获取播放时间
 OSStatus AudioQueueGetCurrentTime(AudioQueueRef inAQ,
 AudioQueueTimelineRef inTimeline,
 AudioTimeStamp * outTimeStamp,
 Boolean * outTimelineDiscontinuity);
 传入的参数中，第一、第四个参数是和AudioQueueTimeline相关的我们这里并没有用到，传入NULL。调用后的返回AudioTimeStamp，从这个timestap结构可以得出播放时间，计算方法如下：
 
 
 销毁AudioQueue
 AudioQueueDispose(AudioQueueRef inAQ,  Boolean inImmediate);
 销毁的同时会清除其中所有的buffer，第二个参数的意义和用法与AudioQueueStop方法相同。
 这个方法使用时需要注意当AudioQueueStart调用之后AudioQueue其实还没有真正开始，期间会有一个短暂的间隙。如果在AudioQueueStart调用后到AudioQueue真正开始运作前的这段时间内调用AudioQueueDispose方法的话会导致程序卡死。这个问题是我在使用AudioStreamer时发现的，在iOS 6必现（iOS 7我倒是没有测试过，当时发现问题时iOS 7还没发布），起因是由于AudioStreamer会在音频EOF时就进入Cleanup环节，Cleanup环节会flush所有数据然后调用Dispose，那么当音频文件中数据非常少时就有可能出现AudioQueueStart调用之时就已经EOF进入Cleanup，此时就会出现上述问题。
 要规避这个问题第一种方法是做好线程的调度，保证Dispose方法调用一定是在每一个播放RunLoop之后（即至少是一个buffer被成功播放之后）。第二种方法是监听kAudioQueueProperty_IsRunning属性，这个属性在AudioQueue真正运作起来之后会变成1，停止后会变成0，所以需要保证Start方法调用后Dispose方法一定要在IsRunning为1时才能被调用。
*/









