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



//#include <pthread.h>
//#import "BNRAudioData.h"
//#import <AudioUnit/AudioUnit.h>

// NSLog control
#if 1 // 1 enable NSLog, 0 disable NSLog
#define NSLog(FORMAT, ...) fprintf(stderr,"[%s:%d]\t%s\n",[[[NSString stringWithUTF8String:__FILE__] lastPathComponent] UTF8String], __LINE__, [[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);
#else
#define NSLog(FORMAT, ...) nil
#endif



/**
 *  缓存区的个数，一般3个
 */
#define kNumberAudioQueueBuffers 3

/**
 *  采样率，要转码为amr的话必须为8000
 */
#define kDefaultSampleRate 44100




@interface FLAudioQueueHelpClass()
{
    AudioStreamBasicDescription     _pcmFormatDes;      ///< PCM format
    AudioStreamBasicDescription     _accFormatDes;      ///< ACC format
    AudioConverterRef               _encodeConvertRef;  ///PCM转ACC的编码器

    
    AudioQueueBufferRef     _inputBuffers[kNumberAudioQueueBuffers];
    AudioQueueBufferRef     _outputBuffers[kNumberAudioQueueBuffers];

    
    NSMutableArray *_reusableBuffers;


}
@property (assign, nonatomic) AudioQueueRef inputQueue;
@property (assign, nonatomic) AudioQueueRef outputQueue;
@property (strong, nonatomic) NSMutableArray *receiveData;//接收数据的数组

@property (strong, nonatomic) NSLock *synclockIn;
@property (strong, nonatomic) NSLock *synclockOut;//播放的bufffer同步
@property (strong, nonatomic) NSLock *synclockPlay;

@property (assign, nonatomic) BOOL isSettingSpeaker;



@property (nonatomic,assign) BOOL startRecord;
@property (nonatomic,assign) BOOL startPlay;



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
        _synclockPlay = [[NSLock alloc] init];
        _isSettingSpeaker = NO;
        [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
        [self initAVAudioSession];
        //设置录音的参数
        [self setupPCMAudioFormat];
        [self setupACCAudioFormat];
        

    }
    return self;
}




#pragma mark  - 设置音频输入输出参数

#pragma mark  initAVAudioSession


- (void)initAVAudioSession
{
    NSError *error = nil;
    [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
    //设置audioSession格式 录音播放模式
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    
}


#pragma mark  初始化录音的队列


/**
 生成编码器

 @param sourceDes 音频原格式 PCM
 @param targetDes 音频目标格式 ACC
 */
- (void)makeEncodeAudioConverterSourceDes:(AudioStreamBasicDescription)sourceDes targetDes:(AudioStreamBasicDescription)targetDes
{
// 此处目标格式其他参数均为默认，系统会自动计算，否则无法进入encodeConverterComplexInputDataProc回调
//    AudioStreamBasicDescription sourceDes = _pcmFormatDes;
//    AudioStreamBasicDescription targetDes = _accFormatDes;
    
    OSStatus status     = 0;
    UInt32 targetSize   = sizeof(targetDes);
    status              = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &targetSize, &targetDes);

    
    
    // 选择软件编码
    AudioClassDescription audioClassDes;
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                        sizeof(targetDes.mFormatID),
                                        &targetDes.mFormatID,
                                        &targetSize);
    //    log4cplus_info("pcm","get kAudioFormatProperty_Encoders status:%d",(int)status);
    
    UInt32 numEncoders = targetSize/sizeof(AudioClassDescription);
    AudioClassDescription audioClassArr[numEncoders];
    AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                           sizeof(targetDes.mFormatID),
                           &targetDes.mFormatID,
                           &targetSize,
                           audioClassArr);
    //    log4cplus_info("pcm","wrirte audioClassArr status:%d",(int)status);
    
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
    UInt32 bitRate  = 64000;
    targetSize      = sizeof(bitRate);
    status          = AudioConverterSetProperty(_encodeConvertRef,
                                                kAudioConverterEncodeBitRate,
                                                targetSize, &bitRate);
}


- (void)initRecordAudioQueue
{
    [self makeEncodeAudioConverterSourceDes:_pcmFormatDes targetDes:_accFormatDes];
    
    //创建一个录制音频队列
    AudioQueueNewInput (&_pcmFormatDes,GenericInputCallback,(__bridge void *)self,NULL,NULL,0,&_inputQueue);
//    UInt32   size            = sizeof(dataFormat);
//    OSStatus status = AudioQueueGetProperty(_inputQueue, kAudioQueueProperty_StreamDescription, &dataFormat, &size);

    //创建录制音频队列缓冲区
    for (int i = 0; i < kNumberAudioQueueBuffers; i++) {
//        AudioQueueBufferRef buffer;
//        AudioQueueAllocateBuffer (_inputQueue,1024*2*_pcmFormatDes.mChannelsPerFrame,&buffer);
//        AudioQueueEnqueueBuffer (_inputQueue,(buffer),0,NULL);
        AudioQueueAllocateBuffer (_inputQueue,1024*2*_pcmFormatDes.mChannelsPerFrame,&_inputBuffers[i]);
        AudioQueueEnqueueBuffer (_inputQueue,(_inputBuffers[i]),0,NULL);

    }
    
    
}

// 设置录音格式
- (void)setupPCMAudioFormat
{
    //重置下
    memset(&_pcmFormatDes, 0, sizeof(_pcmFormatDes));
    
    
    //    int tmp = [[AVAudioSession sharedInstance] sampleRate];
    //设置采样率，这里先获取系统默认的测试下 //TODO:
    //采样率的意思是每秒需要采集的帧数
    _pcmFormatDes.mSampleRate = kDefaultSampleRate;
    
    //设置通道数,这里先使用系统的测试下
    UInt32 inputNumberOfChannels = (UInt32)[[AVAudioSession sharedInstance] inputNumberOfChannels];
    _pcmFormatDes.mChannelsPerFrame = inputNumberOfChannels;
    
    //设置format，怎么称呼不知道。
    _pcmFormatDes.mFormatID = kAudioFormatLinearPCM;
    
    _pcmFormatDes.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    //每个通道里，一帧采集的bit数目
    _pcmFormatDes.mBitsPerChannel = 16;
    //结果分析: 8bit为1byte，即为1个通道里1帧需要采集2byte数据，再*通道数，即为所有通道采集的byte数目。
    //所以这里结果赋值给每帧需要采集的byte数目，然后这里的packet也等于一帧的数据。
    _pcmFormatDes.mBytesPerPacket = _pcmFormatDes.mBytesPerFrame = (_pcmFormatDes.mBitsPerChannel / 8) * _pcmFormatDes.mChannelsPerFrame;
    _pcmFormatDes.mFramesPerPacket = 1;// 用AudioQueue采集pcm需要这么设置
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


#pragma mark  初始化播放队列

- (void)initPlayAudioQueue
{
    //创建一个输出队列
    OSStatus status = AudioQueueNewOutput(&_accFormatDes, GenericOutputCallback, (__bridge void *) self, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0,&_outputQueue);
    NSLog(@"status ：%d",status);
    
    //创建并分配缓冲区空间3个缓冲区
    for (int i=0; i < kNumberAudioQueueBuffers; ++i) {
        AudioQueueAllocateBuffer(_outputQueue, 1024*2*_accFormatDes.mChannelsPerFrame, &_outputBuffers[i]);
        makeSilent(_outputBuffers[i]);  //改变数据
//        // 给输出队列完成配置 PCM的方式
//        AudioQueueEnqueueBuffer(_outputQueue,_outputBuffers[i],0,NULL);
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








- (void)setupACCAudioFormat{
    
    
    memset(&_accFormatDes, 0, sizeof(_accFormatDes));
    _accFormatDes.mFormatID                   = kAudioFormatMPEG4AAC;
    _accFormatDes.mSampleRate                 = kDefaultSampleRate;
//    _accFormatDes.mFramesPerPacket            = 1024;
    //设置通道数,这里先使用系统的测试下
    UInt32 inputNumberOfChannels = (UInt32)[[AVAudioSession sharedInstance] inputNumberOfChannels];
    _accFormatDes.mChannelsPerFrame = inputNumberOfChannels;
    
    OSStatus status     = 0;
    UInt32 targetSize   = sizeof(_accFormatDes);
    status              = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &targetSize, &_accFormatDes);
    

    
}




#pragma mark - PCM -> AAC


OSStatus encodeConverterComplexInputDataProc1(AudioConverterRef              inAudioConverter,
                                             UInt32                         *ioNumberDataPackets,
                                             AudioBufferList                *ioData,
                                             AudioStreamPacketDescription   **outDataPacketDescription,
                                             void                           *inUserData) {
    
    
    FLAudioQueueHelpClass *aq = [FLAudioQueueHelpClass shareInstance];

    ioData->mBuffers[0].mData           = inUserData;
    ioData->mBuffers[0].mNumberChannels = aq->_accFormatDes.mChannelsPerFrame;
    ioData->mBuffers[0].mDataByteSize   = 1024*2; // 2 为dataFormat.mBytesPerFrame 每一帧的比特数
    
    return 0;
}

// PCM -> AAC
AudioBufferList* convertPCMToAAC (AudioQueueBufferRef inBuffer) {
    
    FLAudioQueueHelpClass *aq = [FLAudioQueueHelpClass shareInstance];

    UInt32   maxPacketSize    = 0;
    UInt32   size             = sizeof(maxPacketSize);
    OSStatus status;
    
    status = AudioConverterGetProperty(aq->_encodeConvertRef,
                                       kAudioConverterPropertyMaximumOutputPacketSize,
                                       &size,
                                       &maxPacketSize);
    //    log4cplus_info("AudioConverter","kAudioConverterPropertyMaximumOutputPacketSize status:%d \n",(int)status);
    
    AudioBufferList *bufferList             = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    bufferList->mNumberBuffers              = 1;
    bufferList->mBuffers[0].mNumberChannels = aq->_accFormatDes.mChannelsPerFrame;
    bufferList->mBuffers[0].mData           = malloc(maxPacketSize);
    bufferList->mBuffers[0].mDataByteSize   = inBuffer->mAudioDataByteSize;
    
    AudioStreamPacketDescription outputPacketDescriptions;
    
    // inNumPackets设置为1表示编码产生1帧数据即返回，官方：On entry, the capacity of outOutputData expressed in packets in the converter's output format. On exit, the number of packets of converted data that were written to outOutputData. 在输入表示输出数据的最大容纳能力 在转换器的输出格式上，在转换完成时表示多少个包被写入
    UInt32 inNumPackets = 1;
    
    // inNumPackets设置为1表示编码产生1帧数据即返回
    status = AudioConverterFillComplexBuffer(aq->_encodeConvertRef,
                                             encodeConverterComplexInputDataProc1,
                                             inBuffer->mAudioData,
                                             &inNumPackets,
                                             bufferList,
                                             &outputPacketDescriptions);

//    if (status == 0) {
//        NSLog(@"bufferList->mBuffers[0].mDataByteSize :%u",(unsigned int)bufferList->mBuffers[0].mDataByteSize);
//
//    }
//    
    
    return bufferList;
}




#pragma mark - 音频输入输出回调

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
    exit(1);
}



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
        
        
        /*
         inNumPackets 总包数：音频队列缓冲区大小 （在先前估算缓存区大小为2048）/ （dataFormat.mFramesPerPacket (采集数据每个包中有多少帧，此处在初始化设置中为1) * dataFormat.mBytesPerFrame（每一帧中有多少个字节，此处在初始化设置中为每一帧中两个字节）），所以用捕捉PCM数据时inNumPackets为1024。
         注意：如果采集的数据是PCM需要将dataFormat.mFramesPerPacket设置为1，而本例中最终要的数据为AAC,在AAC格式下需要将mFramesPerPacket设置为1024.也就是采集到的inNumPackets为1，所以inNumPackets这个参数在此处可以忽略，因为在转换器中传入的inNumPackets应该为AAC格式下默认的1，在此后写入文件中也应该传的是转换好的inNumPackets。
         */
        
        // collect pcm data，可以在此存储
        
        AudioBufferList *bufferList = convertPCMToAAC(inBuffer);
        
        NSData *accData = [[NSData alloc] initWithBytes:bufferList->mBuffers[0].mData length:bufferList->mBuffers[0].mDataByteSize];
        if([accData length] > 0)
        {
            if ([FLAudioQueueHelpClass shareInstance].recordWithData && [accData length] > 10)
                [FLAudioQueueHelpClass shareInstance].recordWithData(accData);
//            NSLog(@"%@: send data %lu",[[UIDevice currentDevice] name] , [accData length]);

        }
        // free memory
        free(bufferList->mBuffers[0].mData);
        free(bufferList);


        
//        if (inNumberPackets > 0) {
//            NSData *pcmData = [[NSData alloc] initWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
//            //pcm数据不为空时，编码为amr格式
//            if (pcmData && pcmData.length > 0) {
//                NSData *amrData = [RecordAmrCode encodePCMDataToAMRData:pcmData];
//                if ([FLAudioQueueHelpClass shareInstance].recordWithData) {
//                    [FLAudioQueueHelpClass shareInstance].recordWithData(amrData);
//                    
//                }
//            }
//        }
    }
    AudioQueueEnqueueBuffer (inAQ,inBuffer,0,NULL);
//    [aq.synclockOut unlock];
}






// 输出回调、播放回调
void GenericOutputCallback (void                 *inUserData,
                            AudioQueueRef        inAQ,
                            AudioQueueBufferRef  buffer)
{

    
    FLAudioQueueHelpClass *aq = [FLAudioQueueHelpClass shareInstance];
    
    /* AMR 转 PCM 播放的一套逻辑
    if([aq.receiveData count] >8 && !aq.isSettingSpeaker)
    {
        
        NSData *pcmData = nil;
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
        AudioQueueEnqueueBuffer([FLAudioQueueHelpClass shareInstance].outputQueue,inBuffer,0,NULL);
    }
    else
    {
        makeSilent(inBuffer);
        AudioQueueEnqueueBuffer([FLAudioQueueHelpClass shareInstance].outputQueue,inBuffer,0,NULL);
    }
     */
    
    
    
    
    BOOL  couldSignal = NO;
    static int lastIndex = 0;
    static int packageCounte = 8;
    
    if (aq.receiveData.count > packageCounte) {
        lastIndex = 0;
        couldSignal = YES;
    }
    if (couldSignal) {
        @autoreleasepool {
            NSMutableData *data = [[NSMutableData alloc] init];
            AudioStreamPacketDescription *paks = calloc(sizeof(AudioStreamPacketDescription), 8);
            for (int i = 0; i < packageCounte ; i++) {
                @synchronized (aq.receiveData) {
                    NSData *audio = [aq.receiveData firstObject];
                    if (audio) {
                        [data appendData:audio];
                        paks[i].mStartOffset = lastIndex;
                        paks[i].mDataByteSize = (UInt32)[audio length];
                        [aq.receiveData removeObjectAtIndex:0];
                        lastIndex += [audio length];
                    }
                }
            }
            [aq.synclockOut lock];
            memcpy(buffer->mAudioData,[data bytes] , [data length]);
            buffer->mAudioDataByteSize = (UInt32)[data length];
            CheckError(AudioQueueEnqueueBuffer(aq.outputQueue, buffer, 8, paks), "cant enqueue");
            free(paks);
            [aq.synclockOut unlock];
        }
    }
    else{
        [aq.synclockOut lock];
        makeSilent(buffer);

        AudioStreamPacketDescription *paks = calloc(sizeof(AudioStreamPacketDescription), 1);
        paks[0].mStartOffset = 0;
        paks[0].mDataByteSize = 0;
        CheckError(AudioQueueEnqueueBuffer(aq.outputQueue, buffer,1, paks), "cant enqueue");
        [aq.synclockOut unlock];

    }

    
    
    
    //    [synclockIn unlock];
    
}



#pragma mark - Action



- (void)startRecordQueue:(BOOL)startRecord
{
    _startRecord = startRecord;

    if (_startRecord) {
        [self initRecordAudioQueue];
        //开启录制队列
        AudioQueueStart(_inputQueue, NULL);
    }else{
        [_synclockIn lock];
        AudioQueueDispose(_inputQueue, YES);
        [_synclockIn unlock];
    }
    
}

- (void)starPlayQueue:(BOOL)startPlay
{
    _startPlay = startPlay;
    if (_startPlay) {
        @synchronized (_receiveData) {
            [_receiveData removeAllObjects];
            [self initPlayAudioQueue];
            AudioQueueStart(_outputQueue,NULL);//开启播放队列
        }
    }else{
        [_synclockOut lock];
        AudioQueueDispose(_outputQueue, YES);
        [_synclockOut unlock];
    }
 
}


/**
 开始记录和播放队列
 */
- (void)startRecordAndPlayQueue
{
    [self startRecordQueue:YES];
    [self starPlayQueue:YES];
}

/**
 停止播放和录音
 */
- (void)stopRecordAndPlayQueue
{
    [self startRecordQueue:NO];
    [self starPlayQueue:NO];
}



/**
 播放音频数据
 
 @param data 音频流数据
 */
- (void)playAudioData:(NSData *)data
{
    if (_startPlay == NO)
        return;

    //------方法一------------
    @synchronized (_receiveData) {
        [_receiveData addObject:data];
    }
    //------------------------
    
    
}

/**
 设置是否扬声器播放
 */
- (void)setSpeak:(BOOL)on
{
    
    [_synclockOut lock];
    
    _isSettingSpeaker = YES;
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
 
 
 pthread_cond_wait() 用于阻塞当前线程，等待别的线程使用pthread_cond_signal()或pthread_cond_broadcast来唤醒它。 pthread_cond_wait() 必须与pthread_mutex 配套使用。pthread_cond_wait()函数一进入wait状态就会自动release mutex。当其他线程通过pthread_cond_signal()或pthread_cond_broadcast，把该线程唤醒，使pthread_cond_wait()通过（返回）时，该线程又自动获得该mutex。
 pthread_cond_signal函数的作用是发送一个信号给另外一个正在处于阻塞等待状态的线程,使其脱离阻塞状态,继续执行.如果没有线程处在阻塞等待状态,pthread_cond_signal也会成功返回。
 使用pthread_cond_signal一般不会有“惊群现象”产生，他最多只给一个线程发信号。假如有多个线程正在阻塞等待着这个条件变量的话，那么是根据各等待线程优先级的高低确定哪个线程接收到信号开始继续执行。如果各线程优先级相同，则根据等待时间的长短来确定哪个线程获得信号。但无论如何一个pthread_cond_signal调用最多发信一次。

 
 
 AVAudioSessionCategoryAmbient      混音播放，可以与其他音频应用同时播放	否	是	是
 AVAudioSessionCategorySoloAmbient	独占播放	否	是	是
 AVAudioSessionCategoryPlayback     后台播放，也是独占的	否	是	否
 AVAudioSessionCategoryRecord       录音模式，用于录音时使用	是	否	否
 AVAudioSessionCategoryPlayAndRecord	播放和录音，此时可以录音也可以播放	是	是	否
 AVAudioSessionCategoryAudioProcessing	硬件解码音频，此时不能播放和录制	否	否	否
 AVAudioSessionCategoryMultiRoute	多种输入输出，例如可以耳机、USB设备同时播放	是	是	否
 
 
 
 
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



