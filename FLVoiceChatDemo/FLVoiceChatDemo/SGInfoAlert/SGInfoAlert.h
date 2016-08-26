//
//  SGInfoAlert.m
//
//  这个类是写提示信息用的。

//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define kSGInfoAlert_fontSize       13
#define kSGInfoAlert_width          200
#define kMax_ConstrainedSize        CGSizeMake(200, 100)

@interface SGInfoAlert : UIView{
    CGColorRef bgcolor_;
    NSString *info_;
    CGSize fontSize_;
}

// info为提示信息，frame为提示框大小，view是为消息框的superView（推荐Tabbarcontroller.view)
// vertical 为垂直方向上出现的位置 从 取值 0 ~ 1。
+ (void)showInfo:(NSString*)info
         bgColor:(CGColorRef)color
          inView:(UIView*)view
        vertical:(float)height;



@end
