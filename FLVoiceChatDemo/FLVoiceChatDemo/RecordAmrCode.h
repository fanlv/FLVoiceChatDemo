//
//  RecordAmrCode.h
//  VoiceChat
//
//  Created by MacOS on 14-9-15.
//  Copyright (c) 2014年 MacOS. All rights reserved.
//

/**
 *  使用audioqueque来实时录音，边录音边转码，可以设置自己的转码方式。从PCM数据转
 */

#import <Foundation/Foundation.h>
@interface RecordAmrCode : NSObject

//将PCM格式Data进行编码，转换为AMR格式
- (NSData *)encodePCMDataToAMRData:(NSData *)pcmData;

//讲AMR格式Data解码，转换为PCM格式
- (NSData *)decodeAMRDataToPCMData:(NSData *)amrData;

typedef struct _RTP_header
{
    /* byte 0 */
#if (BYTE_ORDER == LITTLE_ENDIAN)
    unsigned char csrc_len:4;   /* expect 0 */
    unsigned char extension:1;  /* expect 1, see RTP_OP below */
    unsigned char padding:1;	/* expect 0 */
    unsigned char version:2;	/* expect 2 */
#elif (BYTE_ORDER == BIG_ENDIAN)
    unsigned char version:2;	/* 版本号 */
    unsigned char padding:1;	/* 填充 */
    unsigned char extension:1;	/* 填充头 */
    unsigned char csrc_len:4;	/* 作用源个数 */
#else
#error Neither big nor little
#endif
    /* byte 1 */
#if (BYTE_ORDER == LITTLE_ENDIAN)
    unsigned char payload:7;	/*  */
    unsigned char marker:1;		/*except 1  */
#elif (BYTE_ORDER == BIG_ENDIAN)
    unsigned char marker:1;		/* 帧边界标识 */
    unsigned char payload:7;	/* 负载类型 */
#endif
    /* bytes 2, 3 */
    unsigned short seq_no;		/* 序列号*/
    /* bytes 4-7 */
    unsigned int timestamp;		/* 时间 */
    /* bytes 8-11 */
    unsigned int ssrc;			/* stream number is used here. */
} RTP_header;

@end
