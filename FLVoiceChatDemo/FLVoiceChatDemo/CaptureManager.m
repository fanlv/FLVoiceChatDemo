//
//  CaptureManager.m
//  IFlyFaceDemo
//
//  Created by 张剑 on 15/7/10.
//  Copyright (c) 2015年 iflytek. All rights reserved.
//

#import "CaptureManager.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <OpenGLES/EAGL.h>
#import <Endian.h>
//#import "UIImage+Extensions.h"
//#import "PermissionDetector.h"
//#import "IFlyFaceImage.h"

//custom Context
static void * SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;
static void * CapturingStillImageContext =&CapturingStillImageContext;

@interface CaptureManager ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@end


@implementation CaptureManager

@synthesize session;
@synthesize previewLayer;

#pragma mark - Capture Session Configuration

- (id)init {
    if ((self = [super init])) {
        self.session=[[AVCaptureSession alloc] init];
        self.lockInterfaceRotation=NO;
        self.previewLayer=[[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    }
    return self;
}

- (void)dealloc {
    [self teardown];
}

#pragma mark -
- (void)setup{
    
    // Check for device authorization
//    [self checkDeviceAuthorizationStatus];
    
    
    // 这里使用CoreMotion来获取设备方向以兼容iOS7.0设备
    self.motionManager = [[CMMotionManager alloc] init];
    self.motionManager.accelerometerUpdateInterval = .2;
    self.motionManager.gyroUpdateInterval = .2;
    
    [self.motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue currentQueue]
                                        withHandler:^(CMAccelerometerData  *accelerometerData, NSError *error) {
                                            if (!error) {
                                                [self updateAccelertionData:accelerometerData.acceleration];
                                            }
                                            else{
                                                NSLog(@"%@", error);
                                            }
                                        }];
    
    // session
    dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
    [self setSessionQueue:sessionQueue];
    
    dispatch_async(sessionQueue, ^{
        [self setBackgroundRecordingID:UIBackgroundTaskInvalid];
        [self.session beginConfiguration];
        
        if([session canSetSessionPreset:AVCaptureSessionPreset640x480]){
            [session setSessionPreset:AVCaptureSessionPreset640x480];
        }

        NSError *error = nil;
        AVCaptureDevice *videoDevice = [CaptureManager deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionFront];
        
        //input device
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        if (error){
            NSLog(@"%@", error);
        }
        if ([session canAddInput:videoDeviceInput]){
            [session addInput:videoDeviceInput];
            [self setVideoDeviceInput:videoDeviceInput];
        }
        
         //output device
        AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        if ([session canAddOutput:videoDataOutput]){
            [session addOutput:videoDataOutput];
            AVCaptureConnection *connection = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
            if ([connection isVideoStabilizationSupported]){
                [connection setEnablesVideoStabilizationWhenAvailable:YES];
            }
            
            if ([connection isVideoOrientationSupported]){
                connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            }
            
            
            // Configure your output.
            
           self.videoDataOutputQueue = dispatch_queue_create("videoDataOutput", NULL);
            [videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
            // Specify the pixel format
            
            
            // Specify the pixel format
            videoDataOutput.videoSettings = [NSDictionary dictionaryWithObject: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
//            //获取灰度图像数据
//            videoDataOutput.videoSettings =[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]forKey:(id)kCVPixelBufferPixelFormatTypeKey];
            [self setVideoDataOutput:videoDataOutput];
        }
        
        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        if ([session canAddOutput:stillImageOutput]){
            [stillImageOutput setOutputSettings:@{AVVideoCodecKey : AVVideoCodecJPEG}];
            [session addOutput:stillImageOutput];
            [self setStillImageOutput:stillImageOutput];
        }
        
        [self.session commitConfiguration];
        
    });
    
}

- (void)teardown{
    [self.session stopRunning];
    self.videoDeviceInput=nil;
    self.videoDataOutput=nil;
    self.videoDataOutputQueue=nil;
    self.sessionQueue=nil;
    [self.previewLayer removeFromSuperlayer];
    self.session=nil;
    self.previewLayer=nil;
    
    [self.motionManager stopAccelerometerUpdates];
    self.motionManager=nil;
}

- (void)addObserver{
    
    dispatch_async([self sessionQueue], ^{
        [self addObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:SessionRunningAndDeviceAuthorizedContext];
        
        __weak CaptureManager *weakSelf = self;
        [self setRuntimeErrorHandlingObserver:[[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:self.session queue:nil usingBlock:^(NSNotification *note) {
            CaptureManager *strongSelf = weakSelf;
            dispatch_async(strongSelf.sessionQueue, ^{
                // Manually restarting the session since it must have been stopped due to an error.
                [strongSelf.session startRunning];
            });
        }]];
        [self.session startRunning];
    });
}

- (void)removeObserver{
    dispatch_async(self.sessionQueue, ^{
        [self.session stopRunning];
        
        [[NSNotificationCenter defaultCenter] removeObserver:[self runtimeErrorHandlingObserver]];
        [self removeObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" context:SessionRunningAndDeviceAuthorizedContext];
    });
}

#pragma mark -
-(BOOL)isSessionRunningAndDeviceAuthorized{
    return [self.session isRunning] && [self isDeviceAuthorized];
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized{
    return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    
    if (context == CapturingStillImageContext){
        BOOL boolValue = [change[NSKeyValueChangeNewKey] boolValue];
        if (boolValue){
            [self runStillImageCaptureAnimation];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            CaptureContextType type= CaptureSessionContextTypeCapturingStillImage;
            if([self delegate] && [self.delegate respondsToSelector:@selector(observerContext:Changed:)]){
                [self.delegate observerContext:type Changed:boolValue];
            }
        });
        
    }
    else if (context == SessionRunningAndDeviceAuthorizedContext){
        BOOL boolValue = [change[NSKeyValueChangeNewKey] boolValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            CaptureContextType type=CaptureContextTypeRunningAndDeviceAuthorized;
            if(self.delegate && [self.delegate respondsToSelector:@selector(observerContext:Changed:)]){
                [self.delegate observerContext:type Changed:boolValue];
            }
        });
    }
    else{
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


// 通过抽样缓存数据创建一个UIImage对象
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    // 为媒体数据设置一个CMSampleBuffer的Core Video图像缓存对象
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // 锁定pixel buffer的基地址
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // 得到pixel buffer的基地址
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // 得到pixel buffer的行字节数
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // 得到pixel buffer的宽和高
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // 创建一个依赖于设备的RGB颜色空间
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // 用抽样缓存的数据创建一个位图格式的图形上下文（graphics context）对象
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // 根据这个位图context中的像素数据创建一个Quartz image对象
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // 解锁pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // 释放context和颜色空间
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // 用Quartz image创建一个UIImage对象image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // 释放Quartz image对象
    CGImageRelease(quartzImage);
    
    return (image);
}


+ (AVCaptureVideoOrientation)interfaceOrientationToVideoOrientation:(UIInterfaceOrientation)orientation {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
        default:
            break;
    }
    NSLog(@"Warning - Didn't recognise interface orientation (%ld)",(long)orientation);
    return AVCaptureVideoOrientationPortrait;
}

#pragma mark - Actions
- (IBAction)snapStillImage{
    dispatch_async([self sessionQueue], ^{
        // Update the orientation on the still image output video connection before capturing.
        [[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[[(AVCaptureVideoPreviewLayer *)[self previewLayer] connection] videoOrientation]];
        
        // Flash set to Auto for Still Capture
        [CaptureManager setFlashMode:AVCaptureFlashModeAuto forDevice:[[self videoDeviceInput] device]];
        
        //去掉声音
        static SystemSoundID soundID = 0;
        if (soundID == 0) {
            NSString *path = [[NSBundle mainBundle] pathForResource:@"photoShutter2" ofType:@"caf"];
            NSURL *filePath = [NSURL fileURLWithPath:path isDirectory:NO];
            AudioServicesCreateSystemSoundID((__bridge CFURLRef)filePath, &soundID);
        }
        AudioServicesPlaySystemSound(soundID);
        
        
        
        
        // Capture a still image.
        [[self stillImageOutput] captureStillImageAsynchronouslyFromConnection:[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
            
            if (imageDataSampleBuffer){
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                UIImage *image = [[UIImage alloc] initWithData:imageData];
                
                //如果是前置摄像头水平翻转照片
                if(self.videoDeviceInput.device.position==AVCaptureDevicePositionFront){
//                    image=[image horizontalFlip];
                }
                if(self.delegate &&[self.delegate respondsToSelector:@selector(stillImageCaptured:)]){
                    [self.delegate stillImageCaptured:image];
                }
            }
        }];
    });
}

- (void)cameraToggle{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        CaptureContextType type=CaptureContextTypeCameraFrontOrBackToggle;
        if(self.delegate && [self.delegate respondsToSelector:@selector(observerContext:Changed:)]){
            [self.delegate observerContext:type Changed:NO];
        }
    });
    
    dispatch_async(self.sessionQueue, ^{
        AVCaptureDevice *currentVideoDevice = self.videoDeviceInput.device;
        AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
        AVCaptureDevicePosition currentPosition = [currentVideoDevice position];
        
        switch (currentPosition){
            case AVCaptureDevicePositionUnspecified:
                preferredPosition = AVCaptureDevicePositionFront;
                break;
            case AVCaptureDevicePositionBack:
                preferredPosition = AVCaptureDevicePositionFront;
                break;
            case AVCaptureDevicePositionFront:
                preferredPosition = AVCaptureDevicePositionBack;
                break;
        }
        
        AVCaptureDevice *videoDevice = [CaptureManager deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
        
        
        [self.session beginConfiguration];
        
        [self.session removeInput:self.videoDeviceInput];
        if ([self.session canAddInput:videoDeviceInput]){
            [self.session addInput:videoDeviceInput];
            [self setVideoDeviceInput:videoDeviceInput];
        }
        else{
            [self.session addInput:self.videoDeviceInput];
        }
        
        if([self.session canSetSessionPreset:AVAssetExportPreset640x480]){
            [self.session setSessionPreset:AVAssetExportPreset640x480];
        }
        
        [self.session commitConfiguration];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            CaptureContextType type=CaptureContextTypeCameraFrontOrBackToggle;
            if(self.delegate && [self.delegate respondsToSelector:@selector(observerContext:Changed:)]){
                [self.delegate observerContext:type Changed:YES];
            }
        });
    });
}

#pragma mark - VideoData OutputSampleBuffer Delegate
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    
    if(self.delegate && [self.delegate respondsToSelector:@selector(onOutputFaceImage:)]){
        UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
        
        UIImageOrientation g_orientation = UIImageOrientationUp;
        if (self.interfaceOrientation == UIInterfaceOrientationLandscapeRight) {
            g_orientation = UIImageOrientationUp;
        }else if (self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft){
            g_orientation = UIImageOrientationDown;
        }else if (self.interfaceOrientation == UIDeviceOrientationPortrait){
            g_orientation = UIImageOrientationRight;
        }else if (self.interfaceOrientation == UIDeviceOrientationPortraitUpsideDown){
            g_orientation = UIImageOrientationLeft;
        }
        image = [[UIImage alloc]initWithCGImage:image.CGImage scale:1.0 orientation:g_orientation];

        [self.delegate onOutputFaceImage:image];

    }
}

#pragma mark - Device Configuration

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position{
    
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = [devices firstObject];
    
    for (AVCaptureDevice *device in devices){
        if ([device position] == position){
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device{
    
    if ([device hasFlash] && [device isFlashModeSupported:flashMode]){
        NSError *error = nil;
        if ([device lockForConfiguration:&error]){
            [device setFlashMode:flashMode];
            [device unlockForConfiguration];
        }
        else{
            NSLog(@"%@", error);
        }
    }
}

#pragma mark - UI

-(void)showAlert:(NSString*)info{
    UIAlertView * alert = [[UIAlertView alloc] initWithTitle:@"提示" message:info delegate:self cancelButtonTitle:@"确定" otherButtonTitles:nil, nil];
    [alert show];
    alert=nil;
}



- (void)runStillImageCaptureAnimation{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self previewLayer] setOpacity:0.0];
        [UIView animateWithDuration:.25 animations:^{
            [[self previewLayer]  setOpacity:1.0];
        }];
    });
}


#pragma mark - tool

- (void)updateAccelertionData:(CMAcceleration)acceleration{
    UIInterfaceOrientation orientationNew;
    
    if (acceleration.x >= 0.75) {
        orientationNew = UIInterfaceOrientationLandscapeLeft;
    }
    else if (acceleration.x <= -0.75) {
        orientationNew = UIInterfaceOrientationLandscapeRight;
    }
    else if (acceleration.y <= -0.75) {
        orientationNew = UIInterfaceOrientationPortrait;
    }
    else if (acceleration.y >= 0.75) {
        orientationNew = UIInterfaceOrientationPortraitUpsideDown;
    }
    else {
        // Consider same as last time
        return;
    }
    
    if (orientationNew == self.interfaceOrientation)
        return;
    
    self.interfaceOrientation = orientationNew;
}

//-(IFlyFaceDirectionType)faceImageOrientation{
//    
//    IFlyFaceDirectionType faceOrientation=IFlyFaceDirectionTypeLeft;
//    BOOL isFrontCamera=self.videoDeviceInput.device.position==AVCaptureDevicePositionFront;
//    switch (self.interfaceOrientation) {
//        case UIDeviceOrientationPortrait:{//
//            faceOrientation=IFlyFaceDirectionTypeLeft;
//        }
//            break;
//        case UIDeviceOrientationPortraitUpsideDown:{
//            faceOrientation=IFlyFaceDirectionTypeRight;
//        }
//            break;
//        case UIDeviceOrientationLandscapeRight:{
//            faceOrientation=isFrontCamera?IFlyFaceDirectionTypeUp:IFlyFaceDirectionTypeDown;
//        }
//            break;
//        default:{//
//            faceOrientation=isFrontCamera?IFlyFaceDirectionTypeDown:IFlyFaceDirectionTypeUp;
//        }
//            
//            break;
//    }
//    
//    return faceOrientation;
//}

@end
