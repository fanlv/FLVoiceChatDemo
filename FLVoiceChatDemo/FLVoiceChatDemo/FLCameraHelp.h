//
//  FLCameraHelp.h
//  Droponto
//
//  Created by Fan Lv on 14-5-22.
//  Copyright (c) 2014年 Haoqi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>


@protocol FLCameraHelpDelegate <NSObject>

///拍完照片后的图像
- (void)didFinishedCapture:(UIImage *)img;
@optional
- (void)foucusStatus:(BOOL)isadjusting;

@end


@interface FLCameraHelp : NSObject

@property (strong,nonatomic) AVCaptureSession *session;
@property (strong,nonatomic) AVCaptureStillImageOutput *captureOutput;
@property (strong,nonatomic) UIImage *image;
@property (assign,nonatomic) UIImageOrientation g_orientation;
@property (assign,nonatomic) AVCaptureVideoPreviewLayer *preview;
@property (assign,nonatomic) id<FLCameraHelpDelegate>delegate;



///开始使用摄像头取景
- (void) startRunning;

///停止使用摄像头取景
- (void) stopRunning;

///拍照
-(void)captureStillImage;

///把摄像头取景的图像添到aView上显示
- (void)embedPreviewInView: (UIView *) aView;

///改变摄像头方向
- (void)changePreviewOrientation:(UIInterfaceOrientation)interfaceOrientation;

///切换前后摄像头
- (BOOL)switchCamera;

///设置闪光点灯模式
- (void)setFlashLightMode:(int)mode;

@end
