//
//  VideoViewController.h
//  FLVoiceChatDemo
//
//  Created by VanRo on 16/8/30.
//  Copyright © 2016年 Fanlv. All rights reserved.
//


#define SCREENBOUNDS                    [[UIScreen mainScreen] bounds];
#define SCREEN_HEIGHT                   [[UIScreen mainScreen] bounds].size.height
#define SCREEN_WIDTH                    [[UIScreen mainScreen] bounds].size.width
#define DEVICE_IS_IPHONE4               ([[UIScreen mainScreen] bounds].size.height == 480)
#define DEVICE_IS_IPHONE5               ([[UIScreen mainScreen] bounds].size.height == 568)
#define DEVICE_IS_IPHONE6               ([[UIScreen mainScreen] bounds].size.height == 667)
#define DEVICE_IS_IPHONE6P              ([[UIScreen mainScreen] bounds].size.height == 736)
#define APP_Bundle_Identifier           [[NSBundle mainBundle] bundleIdentifier]


#define APP_VERSION                     [NSString stringWithString:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]]
#define APP_BUILD_VERSION               [NSString stringWithString:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]]

#define RGB(r,g,b)                      [UIColor colorWithRed:(r)/255.0f green:(g)/255.0f blue:(b)/255.0f alpha:1]
#define RGBA(r,g,b,a)                   [UIColor colorWithRed:(r)/255.0f green:(g)/255.0f blue:(b)/255.0f alpha:a]
#define OS_VERSION                      [[[UIDevice currentDevice] systemVersion] floatValue]
#define APP_DELEGATE                    ((AppDelegate*)[[UIApplication sharedApplication] delegate])
#define UserDefaultGet(s)               [[NSUserDefaults standardUserDefaults] valueForKey:s]
#define UserDefaultSet(key,value)       [[NSUserDefaults standardUserDefaults] setValue:value forKey:key]
#define SCREEN_SCALE                    [[UIScreen mainScreen] bounds].size.width/320.0
#define AssetImage(path)                (path).length > 0 ? [UIImage imageNamed:(path)] : nil
#define SystemFontOfSize(s)             [UIFont systemFontOfSize:s+Font_SCALE]
#define Font_SCALE                      (DEVICE_IS_IPHONE4?.5:(DEVICE_IS_IPHONE5?.5:(DEVICE_IS_IPHONE6?1:(DEVICE_IS_IPHONE6P?2:1))))

#define FLDicWithOAndK(firstObject, ...) [NSDictionary dictionaryWithObjectsAndKeys:firstObject, ##__VA_ARGS__, nil];

#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

#define SCREEN_WIDTH_SCALE_IP6S          [[UIScreen mainScreen] bounds].size.width/414.0
#define SCREEN_HEIGHT_SCALE_IP6S         [[UIScreen mainScreen] bounds].size.height/736.0



#import <UIKit/UIKit.h>

@interface VideoViewController : UIViewController


@property (nonatomic,strong) NSString *ipStr;

@end



















