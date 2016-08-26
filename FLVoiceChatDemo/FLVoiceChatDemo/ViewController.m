//
//  ViewController.m
//  FLVoiceChatDemo
//
//  Created by Fan Lv on 16/8/26.
//  Copyright © 2016年 Fanlv. All rights reserved.
//

#import "ViewController.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#import "RecordAmrCode.h"
#import "GCDAsyncUdpSocket.h"


/**
 *  缓存区的个数，一般3个
 */
#define kNumberAudioQueueBuffers 6

/**
 *  采样率，要转码为amr的话必须为8000
 */
#define kDefaultSampleRate 8000

#define kDefaultInputBufferSize 8000

#define kDefaultOutputBufferSize 8000

#define kDefaultPort  8080

@interface ViewController ()<GCDAsyncUdpSocketDelegate>
{
    AudioQueueRef                   _inputQueue;
    AudioQueueRef                   _outputQueue;
    AudioStreamBasicDescription     _audioFormat;
    
    AudioQueueBufferRef     _inputBuffers[kNumberAudioQueueBuffers];
    AudioQueueBufferRef     _outputBuffers[kNumberAudioQueueBuffers];
    
    
}

@property (weak, nonatomic) IBOutlet UILabel *tipLabel;
@property (weak, nonatomic) IBOutlet UITextField *ipTF;

@property (strong, nonatomic) GCDAsyncUdpSocket             *udpSocket;

@property (assign, nonatomic) AudioQueueRef                 inputQueue;
@property (assign, nonatomic) AudioQueueRef                 outputQueue;
@property (strong, nonatomic) RecordAmrCode                 *recordAmrCode;

@property (nonatomic,strong) UITapGestureRecognizer   *singleTap;

@end

@implementation ViewController
NSMutableArray *receiveData;//接收数据的数组
BOOL isStartSend;
NSLock *synclock;


- (UITapGestureRecognizer *)singleTap
{
    if (_singleTap == nil)
    {
        _singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewDidTap:)];
        [self.view addGestureRecognizer:_singleTap];
    }
    return _singleTap;
}


- (void)viewDidTap:(UITapGestureRecognizer *)sender
{
    [self.view endEditing:YES];
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    synclock = [[NSLock alloc] init];
    //socket
    self.udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    //绑定端口
    [self.udpSocket bindToPort:kDefaultPort error:nil];
    
    if (_recordAmrCode == nil) {
        _recordAmrCode = [[RecordAmrCode alloc] init];
    }
    
    self.singleTap.enabled = YES;
    //添加近距离事件监听，添加前先设置为YES，如果设置完后还是NO的读话，说明当前设备没有近距离传感器
    [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
    if ([UIDevice currentDevice].proximityMonitoringEnabled == YES) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sensorStateChange:)name:UIDeviceProximityStateDidChangeNotification object:nil];
    }

}
#pragma mark - 处理近距离监听触发事件
-(void)sensorStateChange:(NSNotificationCenter *)notification;
{
//    //如果此时手机靠近面部放在耳朵旁，那么声音将通过听筒输出，并将屏幕变暗（省电啊）
//    if ([[UIDevice currentDevice] proximityState] == YES)//黑屏
//    {
//        NSLog(@"Device is close to user");
//        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
//        
//    }
//    else//没黑屏幕
//    {
//        NSLog(@"Device is not close to user");
//        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
//        
//    }
}
#pragma mark - ACTION

- (IBAction)startRecord:(id)sender
{
    if (isStartSend == NO) {
        isStartSend = YES;
        
        receiveData = nil;
        receiveData = [[NSMutableArray alloc] init];
        if (_recordAmrCode == nil) {
            _recordAmrCode = [[RecordAmrCode alloc] init];
        }

        self.tipLabel.text = @"开始录音和播放录音";
        
        //让udpSocket 开始接收数据
        [self.udpSocket beginReceiving:nil];

        
        [self initAudioQueue];
    }
}

- (IBAction)stopRecord:(id)sender
{
    if (isStartSend) {
        isStartSend = NO;

        AudioQueueDispose(_inputQueue, YES);
        AudioQueueDispose(_outputQueue, YES);
        self.tipLabel.text = @"停止录音";

    }

//    //暂停接收数据
//    [self.udpSocket pauseReceiving];
    

}

- (IBAction)playWtihHeadPhone:(UIButton *)sender
{
    [synclock lock];
    
    sender.selected = !sender.selected;
    
    NSLog(@"%@",[[AVAudioSession sharedInstance] category]);
    NSError *error = nil;

    
    if (sender.selected)
    {
//        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        //切换为听筒播放
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
        NSLog(@"切换为听筒模式 %@ ",[error description]);

    }
    else
    {
//        //切换为扬声器播放
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
        NSLog(@"切换为扬声器模式 %@ ",[error description]);
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
//
//        NSLog(@"切换为扬声器模式 %@ ",[error description]);
        
        
        
        
//        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
//        NSLog(@"切换为扬声器模式 overrideOutputAudioPort %@ ",[error description]);
//
//        //设置audioSession格式 录音播放模式
//        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
//        NSLog(@"切换为扬声器模式 setCategory %@ ",[error description]);



    }
    
    
//    AudioQueueStop(_inputQueue,YES);
//    AudioQueueStop(_outputQueue,YES);

    
  

//    //开启录制队列
//    AudioQueueStart(_inputQueue, NULL);
//    //开启播放队列
//    AudioQueueStart(_outputQueue,NULL);

//    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [synclock unlock];
    
    
}

#pragma mark - 音频输入输出回调

- (void)initAudioQueue
{
    //设置录音的参数
    [self setupAudioFormat:kAudioFormatLinearPCM SampleRate:kDefaultSampleRate];
    _audioFormat.mSampleRate = kDefaultSampleRate;

    //创建一个录制音频队列
    AudioQueueNewInput (&_audioFormat,GenericInputCallback,(__bridge void *)self,NULL,NULL,0,&_inputQueue);
    //创建一个输出队列
    AudioQueueNewOutput(&_audioFormat, GenericOutputCallback, (__bridge void *) self, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0,&_outputQueue);

    //设置话筒属性等
//    [self initSession];
    NSError *error = nil;

    //设置audioSession格式 录音播放模式
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    
    [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];

//    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
////    默认情况下扬声器播放
//    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
//    [audioSession setActive:YES error:nil];


    //创建录制音频队列缓冲区
    for (int i = 0; i < kNumberAudioQueueBuffers; i++) {
        AudioQueueAllocateBuffer (_inputQueue,kDefaultInputBufferSize,&_inputBuffers[i]);
        AudioQueueEnqueueBuffer (_inputQueue,(_inputBuffers[i]),0,NULL);
    }
    
    //创建并分配缓冲区空间3个缓冲区
    for (int i=0; i < kNumberAudioQueueBuffers; ++i) {
        AudioQueueAllocateBuffer(_outputQueue, kDefaultOutputBufferSize, &_outputBuffers[i]);

        makeSilent(_outputBuffers[i]);  //改变数据
        // 给输出队列完成配置
        AudioQueueEnqueueBuffer(_outputQueue,_outputBuffers[i],0,NULL);
    }
    
    Float32 gain = 1.0;                                       // 1
    // Optionally, allow user to override gain setting here 设置音量
    AudioQueueSetParameter (_outputQueue,kAudioQueueParam_Volume,gain);
    
    //开启录制队列
    AudioQueueStart(_inputQueue, NULL);
    //开启播放队列
    AudioQueueStart(_outputQueue,NULL);
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
    NSLog(@"录音回调");
    
    [synclock lock];
    
    ViewController *rootCtrl = (__bridge ViewController *)(inUserData);
    if (inNumberPackets > 0) {
        NSData *pcmData = [[NSData alloc] initWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
        //pcm数据不为空时，编码为amr格式
        if (pcmData && pcmData.length > 0) {
            NSData *amrData = [rootCtrl.recordAmrCode encodePCMDataToAMRData:pcmData];
            if (isStartSend) {
                [rootCtrl.udpSocket sendData:amrData toHost:rootCtrl.ipTF.text port:kDefaultPort withTimeout:-1 tag:0];
            }
        }
        
    }
    AudioQueueEnqueueBuffer (inAQ,inBuffer,0,NULL);
    [synclock unlock];
}

// 输出回调
void GenericOutputCallback (
                            void                 *inUserData,
                            AudioQueueRef        inAQ,
                            AudioQueueBufferRef  inBuffer
                            )
{
//    [synclock lock];

    NSLog(@"播放回调");
    ViewController *rootCtrl = (__bridge ViewController *)(inUserData);
    NSData *pcmData = nil;
    
    @synchronized (receiveData) {

        if([receiveData count] >0)
        {
            NSData *amrData = [[receiveData objectAtIndex:0] copy];
            
            pcmData = [rootCtrl.recordAmrCode decodeAMRDataToPCMData:amrData];
            
            if (pcmData) {
                if(pcmData.length < 10000){
                    memcpy(inBuffer->mAudioData, pcmData.bytes, pcmData.length);
                    inBuffer->mAudioDataByteSize = (UInt32)pcmData.length;
                    inBuffer->mPacketDescriptionCount = 0;
                }
            }
            [receiveData removeObjectAtIndex:0];
        }
        else
        {
            makeSilent(inBuffer);
        }
        AudioQueueEnqueueBuffer(rootCtrl.outputQueue,inBuffer,0,NULL);

    
    }

//    [synclock unlock];

}

#pragma mark - 设置音频输入输出参数


// 设置录音格式
- (void)setupAudioFormat:(UInt32) inFormatID SampleRate:(int)sampeleRate
{
    //重置下
    memset(&_audioFormat, 0, sizeof(_audioFormat));
    
    //设置采样率，这里先获取系统默认的测试下 //TODO:
    //采样率的意思是每秒需要采集的帧数
    _audioFormat.mSampleRate = sampeleRate;//[[AVAudioSession sharedInstance] sampleRate];
    
    //设置通道数,这里先使用系统的测试下 //TODO:
    _audioFormat.mChannelsPerFrame = 1;//(UInt32)[[AVAudioSession sharedInstance] inputNumberOfChannels];
    
    //设置format，怎么称呼不知道。
    _audioFormat.mFormatID = inFormatID;
    
    if (inFormatID == kAudioFormatLinearPCM){
        _audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        //每个通道里，一帧采集的bit数目
        _audioFormat.mBitsPerChannel = 16;
        //结果分析: 8bit为1byte，即为1个通道里1帧需要采集2byte数据，再*通道数，即为所有通道采集的byte数目。
        //所以这里结果赋值给每帧需要采集的byte数目，然后这里的packet也等于一帧的数据。
        _audioFormat.mBytesPerPacket = _audioFormat.mBytesPerFrame = (_audioFormat.mBitsPerChannel / 8) * _audioFormat.mChannelsPerFrame;
        _audioFormat.mFramesPerPacket = 1;
    }
    
}



#pragma mark - GCDAsyncUdpSocketDelegate
- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address
withFilterContext:(id)filterContext
{
    @synchronized (receiveData) {
        [receiveData addObject:data];
    }
}

@end







































