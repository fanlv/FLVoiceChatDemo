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
#import "GCDAsyncUdpSocket.h"


#define kVideoDefaultPort  10086


@interface VideoViewController ()<CaptureManagerDelegate,GCDAsyncUdpSocketDelegate>
{
    UIImageView *imageView;
}

@property (nonatomic, retain) CaptureManager *captureManager;
@property (strong, nonatomic) GCDAsyncUdpSocket *udpSocket;

@end

@implementation VideoViewController

- (GCDAsyncUdpSocket *)udpSocket
{
    if (_udpSocket == nil)
    {
        //socket
        _udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        _udpSocket.maxReceiveIPv4BufferSize = 60000;
        _udpSocket.maxReceiveIPv6BufferSize = 60000;

        //绑定端口
        [_udpSocket bindToPort:kVideoDefaultPort error:nil];

        //让udpSocket 开始接收数据
        [_udpSocket beginReceiving:nil];
        
    }
    return _udpSocket;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    
    
    
    
   

    
    //CGRectMake(0, 66, SCREEN_WIDTH, SCREEN_WIDTH)
    imageView = [[UIImageView alloc]  initWithFrame:self.view.bounds];//initWithFrame:CGRectMake(100, 100 +SCREEN_WIDTH , 100, 100)];
    imageView.backgroundColor = RGB(222, 222, 222);
    [self.view addSubview:imageView];
    
    
    NSMutableData *data = [[NSMutableData alloc] init];
    ushort messageAttribute = 0;
    [data appendBytes:&messageAttribute length:sizeof(messageAttribute)];
    [self.udpSocket sendData:data toHost:self.ipStr port:kVideoDefaultPort withTimeout:-1 tag:0];


    
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(SCREEN_WIDTH - 120 -20, SCREEN_HEIGHT - 160 - 50 , 120, 160)];
    view.backgroundColor = RGB(222, 222, 222);
    [self.view addSubview:view];
    
    //初始化 CaptureSessionManager
    self.captureManager=[[CaptureManager alloc] init];
    self.captureManager.delegate=self;
    self.captureManager.previewLayer.frame= view.bounds;
    self.captureManager.previewLayer.videoGravity=AVLayerVideoGravityResizeAspectFill;
    [view.layer addSublayer:self.captureManager.previewLayer];
    
    [self.captureManager setup];

}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.captureManager addObserver];

}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_udpSocket pauseReceiving];
    [_udpSocket setDelegate:nil];
    _udpSocket = nil;
    [self.captureManager teardown];
    
}

#pragma mark - CaptureManagerDelegate



-(void)onOutputFaceImage:(UIImage *)image
{
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSData *data = UIImageJPEGRepresentation(image,.01);
//            NSLog(@"video data :%lu",(unsigned long)[data length]);

            if ([data length] > 9216)
            {
                data = [data subdataWithRange:NSMakeRange(0, 9216)];
            }
            [self.udpSocket sendData:data toHost:self.ipStr port:kVideoDefaultPort withTimeout:-1 tag:0];


        });
        

    });
    

    
}

#pragma mark - GCDAsyncUdpSocketDelegate

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didConnectToAddress:(NSData *)address;
{
    NSLog (@"didConnectToAddress");
}
- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotConnect:(NSError *)error;
{
    NSLog (@"didNotConnect");
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
    NSLog (@"error : %@",[error description]);

}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError  * _Nullable)error
{
    NSLog (@"udpSocketDidClose");
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address
withFilterContext:(id)filterContext
{
//    NSLog(@"video data :%lu",(unsigned long)[data length]);

    dispatch_async(dispatch_get_main_queue(), ^{
        imageView.image = [UIImage imageWithData:data];
    });

}


@end