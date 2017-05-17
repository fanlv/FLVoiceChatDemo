//
//  ViewController.m
//  FLVoiceChatDemo
//
//  Created by Fan Lv on 16/8/26.
//  Copyright © 2016年 Fanlv. All rights reserved.
//

#import "ViewController.h"
#import "VideoViewController.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#import "RecordAmrCode.h"
#import "GCDAsyncUdpSocket.h"
#import "GCDAsyncSocket.h"

#import "FLAudioQueueHelpClass.h"
#import "FLAudioUnitHelpClass.h"




#define DEVICE_IS_IPHONE4               ([[UIScreen mainScreen] bounds].size.height == 480)
#define DEVICE_IS_IPHONE5               ([[UIScreen mainScreen] bounds].size.height == 568)
#define DEVICE_IS_IPHONE6               ([[UIScreen mainScreen] bounds].size.height == 667)
#define DEVICE_IS_IPHONE6P              ([[UIScreen mainScreen] bounds].size.height == 736)


#define kDefaultPort  58080
#define kTCPDefaultPort  58088

@interface ViewController ()<GCDAsyncUdpSocketDelegate,GCDAsyncSocketDelegate>
{
    
//    AVAudioConverterRef m_converter;
//    AWEncoderManager *csdddd;
    BOOL isStartSend;
    
}

@property (weak, nonatomic) IBOutlet UILabel *tipLabel;
@property (weak, nonatomic) IBOutlet UITextField *ipTF;

@property (strong, nonatomic) GCDAsyncUdpSocket             *udpSocket;


@property (nonatomic,strong) UITapGestureRecognizer   *singleTap;


@property (strong, nonatomic) GCDAsyncSocket             *tcpSocket;
@property (strong, nonatomic) GCDAsyncSocket             *acceptSocket;

@end

@implementation ViewController


#pragma mark - Property


- (GCDAsyncUdpSocket *)udpSocket
{
    if (_udpSocket == nil)
    {
        //socket
        _udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        //绑定端口
        [_udpSocket bindToPort:kDefaultPort error:nil];
        //让udpSocket 开始接收数据
        [_udpSocket beginReceiving:nil];
    }
    return _udpSocket;
}


- (GCDAsyncSocket *)tcpSocket
{
    if (_tcpSocket == nil)
    {
        _tcpSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    }
    return _tcpSocket;
}

- (UITapGestureRecognizer *)singleTap
{
    if (_singleTap == nil)
    {
        _singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewDidTap:)];
        [self.view addGestureRecognizer:_singleTap];
    }
    return _singleTap;
}



#pragma mark - View Life Cycle

- (void)viewDidTap:(UITapGestureRecognizer *)sender
{
    [self.view endEditing:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    self.singleTap.enabled = YES;
    
    if (DEVICE_IS_IPHONE6P) {
        _ipTF.text = @"10.100.144.47";
    }
    else
    {
        _ipTF.text = @"10.100.144.59";
    }
    

    NSMutableData *data = [[NSMutableData alloc] init];
    ushort messageAttribute = 0;
    [data appendBytes:&messageAttribute length:sizeof(messageAttribute)];
    [self.udpSocket sendData:data toHost:[_ipTF.text copy] port:kDefaultPort withTimeout:-1 tag:0];


    [FLAudioUnitHelpClass shareInstance].recordWithData = ^(NSData *audioData) {
        if (isStartSend) {
            if ([self.tcpSocket isConnected])
            {
                [self.tcpSocket writeData:[audioData copy] withTimeout:-1 tag:0];
            }
            else if ([self.acceptSocket isConnected])
            {
                [self.acceptSocket writeData:audioData withTimeout:-1 tag:1];
            }
            else
            {
                [self.udpSocket sendData:audioData toHost:[self.ipTF.text copy] port:kDefaultPort withTimeout:-1 tag:0];
            }
        }
        
    };
    

}

#pragma mark - ACTION

- (IBAction)startRecord:(id)sender
{
    if (isStartSend == NO) {
        
        [[FLAudioUnitHelpClass shareInstance] startRecordAndPlayQueue];

        if ([_tcpSocket isConnected]|| [_acceptSocket isConnected]) {
            self.tipLabel.text = @"TCP-开始录音和播放录音";
        }else{
            self.tipLabel.text = @"UDP-开始录音和播放录音";
        }
        isStartSend = YES;

    }
}

- (IBAction)stopRecord:(id)sender
{
    if (isStartSend) {
        isStartSend = NO;
        
        
        [[FLAudioUnitHelpClass shareInstance] stopRecordAndPlayQueue];

       
        
        self.tipLabel.text = @"停止录音";
        
        if ([_tcpSocket isConnected]) {
            [_tcpSocket disconnect];
        }

    }

}

- (IBAction)playWtihHeadPhone:(UIButton *)sender
{
    sender.selected = !sender.selected;
    
    [[FLAudioUnitHelpClass shareInstance] setSpeak:sender.selected];

    
}

- (IBAction)tcpConnect:(id)sender
{
    NSError *error;
    [_tcpSocket disconnect];
    [self.tcpSocket connectToHost:_ipTF.text onPort:kTCPDefaultPort error:&error];
    if (error) {
        NSLog(@"%@",[error description]);
    }
    
}

- (IBAction)startListening:(id)sender
{
    NSError *error;

    [self.tcpSocket acceptOnPort:kTCPDefaultPort error:&error];
    if (error) {
        NSLog(@"%@",[error description]);
    }
    else
    {
        self.tipLabel.text = [NSString stringWithFormat:@"开始监听"];
    }

}

- (IBAction)videoTest:(id)sender
{
    VideoViewController *vc = [[VideoViewController alloc] init];
    vc.ipStr = _ipTF.text;
    [self.navigationController pushViewController:vc animated:YES];
}



#pragma mark - GCDAsyncUdpSocketDelegate

//- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag
//{
//    NSLog (@"DidSend");
//}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address
withFilterContext:(id)filterContext
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
//        if (isStartSend)
        {
            [[FLAudioUnitHelpClass shareInstance] playAudioData:data];
        }
    });
//    NSLog(@"%@: rece data %lu",[[UIDevice currentDevice] name] , [data length]);

  
}


#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    self.tipLabel.text = [NSString stringWithFormat:@"接收到一个Socket连接"];

    _acceptSocket = newSocket;
}

/**
 * Called when a socket connects and is ready for reading and writing.
 * The host parameter will be an IP address, not a DNS name.
 **/
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    self.tipLabel.text = [NSString stringWithFormat:@"%@:%d连接成功",host,port];
}

/**
 * Called when a socket connects and is ready for reading and writing.
 * The host parameter will be an IP address, not a DNS name.
 **/
- (void)socket:(GCDAsyncSocket *)sock didConnectToUrl:(NSURL *)url
{
    NSLog(@"didConnectToUrl : %@",url);
}

/**
 * Called when a socket has completed reading the requested data into memory.
 * Not called if there is an error.
 **/
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    NSLog(@"%@: rece data %lu",[[UIDevice currentDevice] name] , [data length]);

    if (isStartSend) {
        [[FLAudioUnitHelpClass shareInstance] playAudioData:data];
    }
}


- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
//    NSLog(@"发送成功");
    [sock readDataWithTimeout:30 tag:0];

}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(nullable NSError *)err
{
    [self stopRecord:nil];
    self.tipLabel.text = [NSString stringWithFormat:@"TCP连接断开"];
    
}







//#pragma mark - ACC 硬编码相关
//
//
//-(BOOL)createAudioConvert:(CMSampleBufferRef)sampleBuffer { //根据输入样本初始化一个编码转换器
//    if (m_converter != nil)
//    {
//        return TRUE;
//    }
//    
//    AudioStreamBasicDescription inputFormat = *(CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer))); // 输入音频格式
//    AudioStreamBasicDescription outputFormat; // 这里开始是输出音频格式
//    memset(&outputFormat, 0, sizeof(outputFormat));
//    outputFormat.mSampleRate       = inputFormat.mSampleRate; // 采样率保持一致
//    outputFormat.mFormatID         = kAudioFormatMPEG4AAC;    // AAC编码
//    outputFormat.mChannelsPerFrame = 2;
//    outputFormat.mFramesPerPacket  = 1024;                    // AAC一帧是1024个字节
//    
//    AudioClassDescription *desc = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
//    if (AudioConverterNewSpecific(&inputFormat, &outputFormat, 1, desc, &m_converter) != noErr)
//    {
//        NSLog(@"AudioConverterNewSpecific failed");
//        return NO;
//    }
//    
//    return YES;
//}
//-(BOOL)encoderAAC:(CMSampleBufferRef)sampleBuffer aacData:(char*)aacData aacLen:(int*)aacLen { // 编码PCM成AAC
//    if ([self createAudioConvert:sampleBuffer] != YES)
//    {
//        return NO;
//    }
//    
//    CMBlockBufferRef blockBuffer = nil;
//    AudioBufferList  inBufferList;
//    if (CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &inBufferList, sizeof(inBufferList), NULL, NULL, 0, &blockBuffer) != noErr)
//    {
//        NSLog(@"CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer failed");
//        return NO;
//    }
//    // 初始化一个输出缓冲列表
//    AudioBufferList outBufferList;
//    outBufferList.mNumberBuffers              = 1;
//    outBufferList.mBuffers[0].mNumberChannels = 2;
//    outBufferList.mBuffers[0].mDataByteSize   = *aacLen; // 设置缓冲区大小
//    outBufferList.mBuffers[0].mData           = aacData; // 设置AAC缓冲区
//    UInt32 outputDataPacketSize               = 1;
//    if (AudioConverterFillComplexBuffer(m_converter, inputDataProc, &inBufferList, &outputDataPacketSize, &outBufferList, NULL) != noErr)
//    {
//        NSLog(@"AudioConverterFillComplexBuffer failed");
//        return NO;
//    }
//    
//    *aacLen = outBufferList.mBuffers[0].mDataByteSize; //设置编码后的AAC大小
//    CFRelease(blockBuffer);
//    return YES;
//}
//-(AudioClassDescription*)getAudioClassDescriptionWithType:(UInt32)type fromManufacturer:(UInt32)manufacturer { // 获得相应的编码器
//    static AudioClassDescription audioDesc;
//    
//    UInt32 encoderSpecifier = type, size = 0;
//    OSStatus status;
//    
//    memset(&audioDesc, 0, sizeof(audioDesc));
//    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size);
//    if (status)
//    {
//        return nil;
//    }
//    
//    uint32_t count = size / sizeof(AudioClassDescription);
//    AudioClassDescription descs[count];
//    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, descs);
//    for (uint32_t i = 0; i < count; i++)
//    {
//        if ((type == descs[i].mSubType) && (manufacturer == descs[i].mManufacturer))
//        {
//            memcpy(&audioDesc, &descs[i], sizeof(audioDesc));
//            break;
//        }
//    }
//    return &audioDesc;
//}
//OSStatus inputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData,AudioStreamPacketDescription **outDataPacketDescription,  void *inUserData) { //AudioConverterFillComplexBuffer 编码过程中，会要求这个函数来填充输入数据，也就是原始PCM数据
//    AudioBufferList bufferList = *(AudioBufferList*)inUserData;
//    ioData->mBuffers[0].mNumberChannels = 1;
//    ioData->mBuffers[0].mData           = bufferList.mBuffers[0].mData;
//    ioData->mBuffers[0].mDataByteSize   = bufferList.mBuffers[0].mDataByteSize;
//    return noErr;
//}


@end







































