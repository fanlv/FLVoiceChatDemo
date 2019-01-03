//
//  AudioQueueHelpClass.h
//  FLVoiceChatDemo
//
//  Created by Fan Lv on 2017/5/11.
//  Copyright © 2017年 Fanlv. All rights reserved.
//

#import <Foundation/Foundation.h>
#if 1 // 1 enable NSLog, 0 disable NSLog
#define NSLog(FORMAT, ...) fprintf(stderr,"[%s:%d]\t%s\n",[[[NSString stringWithUTF8String:__FILE__] lastPathComponent] UTF8String], __LINE__, [[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);
#else
#define NSLog(FORMAT, ...) nil
#endif

@interface FLAudioQueueHelpClass : NSObject


@property (copy, nonatomic) void (^recordWithData)(NSData *audioData);



/**
  AudioQueueHelpClass单例
 */
+ (instancetype)shareInstance;
/**
 开始录音队列
 */
- (void)startRecordQueue:(BOOL)startRecord;

/**
 开始播放队列
 */
- (void)starPlayQueue:(BOOL)startPlay;
/**
 开始记录和播放队列
 */
- (void)startRecordAndPlayQueue;
/**
 停止播放和录音
 */
- (void)stopRecordAndPlayQueue;


/**
 播放音频数据

 @param data 音频流数据
 */
- (void)playAudioData:(NSData *)data;



/**
 设置是否扬声器播放
 */
- (void)setSpeak:(BOOL)on;


@end
