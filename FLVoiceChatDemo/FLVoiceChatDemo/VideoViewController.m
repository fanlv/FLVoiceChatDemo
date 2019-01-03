//
//  VideoViewController.m
//  FLVoiceChatDemo
//
//  Created by VanRo on 16/8/30.
//  Copyright © 2016年 Fanlv. All rights reserved.
//

#import "VideoViewController.h"
#import "CaptureManager.h"
#import <AVFoundation/AVFoundation.h>
#import "GCDAsyncSocket.h"
#import "FLCameraHelp.h"


#define kVideoDefaultPort  10086


@interface VideoViewController ()<FLCameraHelpDelegate,GCDAsyncSocketDelegate>
{
    UIImageView *imageView;
    NSMutableData *imageData;
    NSMutableData *frameData;
}

@property (nonatomic, strong) CaptureManager *captureManager;
@property (nonatomic, strong) FLCameraHelp *flCameraHelp;
@property (strong, nonatomic) GCDAsyncSocket             *tcpSocket;
@property (strong, nonatomic) GCDAsyncSocket             *acceptSocket;


@end

@implementation VideoViewController

- (GCDAsyncSocket *)tcpSocket
{
    if (_tcpSocket == nil)
    {
        _tcpSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    }
    return _tcpSocket;
}



- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    
    imageData = [[NSMutableData alloc] init];
    
    //CGRectMake(0, 66, SCREEN_WIDTH, SCREEN_WIDTH)
    imageView = [[UIImageView alloc]  initWithFrame:self.view.bounds];//initWithFrame:CGRectMake(100, 100 +SCREEN_WIDTH , 100, 100)];
    imageView.backgroundColor = RGB(222, 222, 222);
    [self.view addSubview:imageView];
    
    
    
    
    
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(SCREEN_WIDTH - 120 -20, SCREEN_HEIGHT - 160 - 50 , 120, 160)];
    view.backgroundColor = RGB(222, 222, 222);
    [self.view addSubview:view];
    
    
    _flCameraHelp = [[FLCameraHelp alloc] init];
    [_flCameraHelp embedPreviewInView:view];
    [_flCameraHelp changePreviewOrientation:[[UIApplication sharedApplication] statusBarOrientation]];
    _flCameraHelp.delegate = self;
    [_flCameraHelp startRunning];
    
    int btnCount = 4;
    int padding = 10;
    float btnW = (SCREEN_WIDTH-padding*(btnCount+1))/btnCount;
    
    for (int i = 0; i<btnCount; i++)
    {
        UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(padding+(btnW+padding)*i, 80, btnW, 40)];
        btn.backgroundColor = [UIColor clearColor];
        [btn addTarget:self action:@selector(btnClick:) forControlEvents:UIControlEventTouchUpInside];
        [btn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        btn.tag = i;
        btn.alpha = .5;
        
        NSString *title = @"";
        if(i == 0)
            title = @"开始监听";
        else if(i == 1)
            title = @"开始连接";
        else if(i == 2)
            title = @"摄像头";
        else if(i == 3)
            title = @"返回";
        [btn setTitle:title forState:UIControlStateNormal];
        [self.view addSubview:btn];

    }
    
    
    
}

- (void)btnClick:(UIButton *)sender
{
    NSLog(@"sender tag %ld",(long)sender.tag);
    if(sender.tag == 0)
    {
        NSError *error;
        
        [self.tcpSocket acceptOnPort:kVideoDefaultPort error:&error];
        if (error) {
            NSLog(@"%@",[error description]);
        }
        else
        {
            self.title = [NSString stringWithFormat:@"端口监听中.."];
        }
    }
    else if(sender.tag == 1)
    {
        NSError *error;
        [_tcpSocket disconnect];
        [self.tcpSocket connectToHost:self.ipStr onPort:kVideoDefaultPort error:&error];
        if (error) {
            NSLog(@"%@",[error description]);
        }
    }
    else if(sender.tag == 2)
    {
        [_flCameraHelp switchCamera];
    }
    else if(sender.tag == 3)
    {
        [_flCameraHelp stopRunning];
        [_tcpSocket disconnect];
//        [self.navigationController popViewControllerAnimated:YES];
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    }
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    [_tcpSocket setDelegate:nil];
    _tcpSocket = nil;
    [_flCameraHelp stopRunning];
    _flCameraHelp.delegate = nil;
    _flCameraHelp = nil;
    
}

#pragma mark - CaptureManagerDelegate



///拍完照片后的图像
- (void)didFinishedCapture:(UIImage *)img;
{
    dispatch_async(dispatch_get_main_queue(), ^{
        imageView.image = img;
    });
    
}


- (void)sendDataTo:(NSData *)data
{
    if (_acceptSocket && [_acceptSocket isConnected])
    {
        [_acceptSocket writeData:data withTimeout:-1 tag:1];
    }
    else if (_tcpSocket && [_tcpSocket isConnected])
    {
        [_tcpSocket writeData:data withTimeout:-1 tag:1];
    }
}

-(void)onOutputImageSteam:(UIImage *)image
{
    static int i= 0;
    i++;
    
//    if (i % 10 == 0)
    {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSData *imageData1 = UIImageJPEGRepresentation(image,.5);
                const unsigned char startBytes[] = {0x7e};//标志位
                NSData *startData = [NSData dataWithBytes:startBytes length:sizeof(startBytes)];
                [self sendDataTo:startData];
                NSData *tData = [self TransferToSendData:imageData1];
                [self sendDataTo:tData];
            });
            
            
        });

    }
    
}






#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    self.title = [NSString stringWithFormat:@"接收到一个Socket连接"];
    
    _acceptSocket = newSocket;

}

/**
 * Called when a socket connects and is ready for reading and writing.
 * The host parameter will be an IP address, not a DNS name.
 **/
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    self.title = [NSString stringWithFormat:@"%@:%d连接成功",host,port];
    [self.tcpSocket readDataWithTimeout:30 tag:0];

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

    [self hanldeReceData:data];

}


- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    if (_acceptSocket == sock) {
        _acceptSocket.delegate = self;
        [_acceptSocket readDataWithTimeout:30 tag:0];

    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(nullable NSError *)err
{
    self.title = [NSString stringWithFormat:@"TCP连接断开"];
}


- (void)hanldeReceData:(NSData *)data
{
    
    if (imageData == nil) {
        imageData = [[NSMutableData alloc] init];
    }
    if (frameData == nil) {
        frameData = [[NSMutableData alloc] init];
    }

    
    @synchronized (imageData)
    {
        [imageData appendData:data];
        for (int i = 0; i < imageData.length; i++)
        {
            Byte tmp = -1;
            [imageData getBytes:&tmp range:NSMakeRange(i, 1)];
            if (tmp == 0x7e)
            {
                if([frameData length]>0)
                {
                    NSData *tmpData = [self RestoreReceData:frameData];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        imageView.image = [UIImage imageWithData:tmpData];
                    });
                }
                //清空数据
                [frameData resetBytesInRange:NSMakeRange(0, frameData.length)];
                [frameData setLength:0];
            }
            else
            {
                [frameData appendBytes:&tmp length:sizeof(Byte)];
            }
            
        }
        
        [imageData resetBytesInRange:NSMakeRange(0, frameData.length)];
        [imageData setLength:0];
    }
    
    
    [self.tcpSocket readDataWithTimeout:30 tag:0];

}



- (void)dealloc
{
    NSLog(@"dealloc");
}



/// Restore ReceData. 0x7e -- 0x7d  0x02；0x7d --- 0x7d  0x01；
- (NSData *)TransferToSendData:(NSData *)messageHeadAndBodyData
{
    NSMutableData *sendData = [[NSMutableData alloc] init];
    
    NSUInteger len = [messageHeadAndBodyData length];
    Byte *realData = (Byte*)malloc(len);
    memcpy(realData, [messageHeadAndBodyData bytes], len);
    
    Byte helpByte_7d = 0x7d;
    Byte helpByte_02 = 0x02;
    Byte helpByte_01 = 0x01;
    
    for (int i = 0; i < len; i++)
    {
        if (realData[i] == 0x7e)
        {
            [sendData appendBytes:&helpByte_7d length:sizeof(Byte)];
            [sendData appendBytes:&helpByte_02 length:sizeof(Byte)];
        }
        else if (realData[i] == 0x7d)
        {
            [sendData appendBytes:&helpByte_7d length:sizeof(Byte)];
            [sendData appendBytes:&helpByte_01 length:sizeof(Byte)];
        }
        else
        {
            [sendData appendBytes:&realData[i] length:sizeof(Byte)];
            
        }
    }
    return sendData;
}


/// Restore ReceData. 0x7d  0x02 -- 0x7e ；0x7d  0x01  --- 0x7d；
/// <returns>realData</returns>
- (NSData *)RestoreReceData:(NSData *)receData
{
    NSMutableData *realData = [[NSMutableData alloc] init];
    
    
    NSUInteger len = [receData length];
    Byte *receDataByteArray = (Byte*)malloc(len);
    memcpy(receDataByteArray, [receData bytes], len);
    
    Byte helpByte_7d = 0x7d;
    Byte helpByte_7e = 0x7e;
    
    for (int i = 0; i < len; i++)
    {
        if (i != len - 1)
        {
            if (receDataByteArray[i] == 0x7d && receDataByteArray[i + 1] == 0x01)
            {
                [realData appendBytes:&helpByte_7d length:sizeof(Byte)];
                i++;
                continue;
            }
            if (receDataByteArray[i] == 0x7d && receDataByteArray[i + 1] == 0x02)
            {
                [realData appendBytes:&helpByte_7e length:sizeof(Byte)];
                i++;
                continue;
            }
        }
        [realData appendBytes:&receDataByteArray[i] length:sizeof(Byte)];
        
    }
    return realData;
}




@end



















