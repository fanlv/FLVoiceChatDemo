//
//  TestVideoCaptureViewController.m
//  FLVoiceChatDemo
//
//  Created by Fan Lv on 2018/3/7.
//  Copyright © 2018年 Fanlv. All rights reserved.
//

#import "TestVideoCaptureViewController.h"
#import "FLCameraHelp.h"

@interface TestVideoCaptureViewController ()<FLCameraHelpDelegate>
@property (nonatomic, strong) FLCameraHelp *flCameraHelp;

@end

@implementation TestVideoCaptureViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    _flCameraHelp = [[FLCameraHelp alloc] init];
    [_flCameraHelp embedPreviewInView:self.view];
//    [_flCameraHelp changePreviewOrientation:UIInterfaceOrientationPortrait];
    [_flCameraHelp changePreviewOrientation:[[UIApplication sharedApplication] statusBarOrientation]];

    _flCameraHelp.delegate = self;
    [_flCameraHelp startRunning];

}

#pragma mark - CaptureManagerDelegate



///拍完照片后的图像
- (void)didFinishedCapture:(UIImage *)img;
{
    
}


- (void)sendDataTo:(NSData *)data
{
 
}

-(void)onOutputImageSteam:(UIImage *)image
{

    
}


#pragma mark - Rotate
//- (BOOL)shouldAutorotate {
//    return YES;
//}
//
//- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
//    return UIInterfaceOrientationMaskLandscape;
//}
//
//- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
//    UIInterfaceOrientation orientation = [self preferredInterfaceOrientationForPresentation];
//    if ((orientation != UIInterfaceOrientationLandscapeLeft) && (orientation != UIInterfaceOrientationLandscapeRight)) {
//        orientation = UIInterfaceOrientationLandscapeRight;
//    }
//    return orientation;
//}


@end
