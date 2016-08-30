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
#import "FLCameraHelp.h"


#define kVideoDefaultPort  10086


@interface VideoViewController ()<FLCameraHelpDelegate,GCDAsyncUdpSocketDelegate>
{
    UIImageView *imageView;
    NSMutableData *imageData;
    NSMutableArray *receDataArray;
}

@property (nonatomic, strong) CaptureManager *captureManager;
@property (strong, nonatomic) GCDAsyncUdpSocket *udpSocket;
@property (nonatomic, strong) FLCameraHelp *flCameraHelp;


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
    
    
    
    
    imageData = [[NSMutableData alloc] init];
    receDataArray = [[NSMutableArray alloc] init];
    [self hanldeReceData];

    
    
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
    
    
    _flCameraHelp = [[FLCameraHelp alloc] init];
    _flCameraHelp = [[FLCameraHelp alloc] init];
    [_flCameraHelp embedPreviewInView:view];
    [_flCameraHelp changePreviewOrientation:[[UIApplication sharedApplication] statusBarOrientation]];
    _flCameraHelp.delegate = self;
    [_flCameraHelp startRunning];
    
    //    //初始化 CaptureSessionManager
    //    self.captureManager=[[CaptureManager alloc] init];
    //    self.captureManager.delegate=self;
    //    self.captureManager.previewLayer.frame= view.bounds;
    //    self.captureManager.previewLayer.videoGravity=AVLayerVideoGravityResizeAspectFill;
    //    [view.layer addSublayer:self.captureManager.previewLayer];
    //
    //    [self.captureManager setup];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    //    [self.captureManager addObserver];
    
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_udpSocket pauseReceiving];
    [_udpSocket setDelegate:nil];
    _udpSocket = nil;
    //    [self.captureManager teardown];
    
}

#pragma mark - CaptureManagerDelegate



///拍完照片后的图像
- (void)didFinishedCapture:(UIImage *)img;
{
    dispatch_async(dispatch_get_main_queue(), ^{
        imageView.image = img;
    });
    
}
-(void)onOutputImageSteam:(UIImage *)image
{
    
    
    static int i= 0;
    i++;
    
    if (i % 5 == 0)
    {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSData *imageData1 = UIImageJPEGRepresentation(image,.5);
                
                
                
                const unsigned char startBytes[] = {0x00};
                NSData *startData = [NSData dataWithBytes:startBytes length:sizeof(startBytes)];
                [self.udpSocket sendData:startData toHost:self.ipStr port:kVideoDefaultPort withTimeout:-1 tag:0];
                
                
                
                static int packageLength = 9000;
                
                
                if ([imageData1 length] <= packageLength)
                {
                    [self.udpSocket sendData:imageData1 toHost:self.ipStr port:kVideoDefaultPort withTimeout:-1 tag:0];
                }
                else
                {
                    NSUInteger length = [imageData1 length];
                    
                    NSUInteger count = length /packageLength;
                    if (length % packageLength != 0) {
                        count++;
                    }
                    
                    for (int i = 0; i < count; i++)
                    {
                        
                        NSData *sendData;
                        if (i == count-1)
                        {
                            NSUInteger lastLength = [imageData1 length]-i*packageLength;
                            sendData = [imageData1 subdataWithRange:NSMakeRange(i*packageLength, lastLength)];
                        }
                        else
                        {
                            sendData = [imageData1 subdataWithRange:NSMakeRange(i*packageLength, packageLength)];
                        }
                        [self.udpSocket sendData:sendData toHost:self.ipStr port:kVideoDefaultPort withTimeout:-1 tag:0];
                        
                    }
                    
                    
                    
                    
                }
                
                
                
                
                
            });
            
            
        });

    }
    
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
    @synchronized (receDataArray) {
        [receDataArray addObject:data];
    }
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self hanldeReceData];
    });

//        NSLog(@"video data :%lu",(unsigned long)[data length]);
    
}

- (void)hanldeReceData
{
    
    //            NSLog(@"receDataArray %lu",(unsigned long)[receDataArray count]);
    
    if ([receDataArray count] > 0)
    {
        @synchronized (receDataArray) {
            @synchronized (imageData) {
                
                while ([receDataArray count] > 0)
                {
                    NSData *data = [receDataArray objectAtIndex:0];
                    if ([data length] == 1)
                    {
                        if ([imageData length] > 0)
                        {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                
                                imageView.image = [UIImage imageWithData:imageData];
                                //                                        NSLog(@"imageData data :%lu",(unsigned long)[imageData length]);
                                imageData = nil;
                                imageData = [[NSMutableData alloc] init];
                                
                            });
                        }
                    }
                }
                else
                {
                    @synchronized (imageData) {
                        [imageData appendData:data];
                    }
                }
                [receDataArray removeObjectAtIndex:0];
            }
        }
    }
    
    
    
    
    
    
    
}


@end



















