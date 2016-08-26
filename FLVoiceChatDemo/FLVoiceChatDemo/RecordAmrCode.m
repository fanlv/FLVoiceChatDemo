//
//  RecordAmrCode.m
//  VoiceChat
//
//  Created by MacOS on 14-9-15.
//  Copyright (c) 2014年 MacOS. All rights reserved.
//

#import "RecordAmrCode.h"

#define PCM_FRAME_SIZE 160 // 8khz 8000*0.02=160
#define MAX_AMR_FRAME_SIZE 32
#define AMR_FRAME_COUNT_PER_SECOND 50

#define AMR_MAGIC_NUMBER "#!AMR\n"

//amr编码、解码
#import "interf_enc.h"
#include "interf_dec.h"

@implementation RecordAmrCode

- (NSData *)encodePCMDataToAMRData:(NSData *)pcmData
{
    void *destate = 0;
    RTP_header rtpHead;
    memset(&rtpHead,0,sizeof(RTP_header));
    rtpHead.marker = 1;
    rtpHead.payload = 0;
    int nLen = 0;
    int nSLen = 0;
    
    // amr 压缩句柄
    destate = Encoder_Interface_init(0);
    if (destate == 0) {
        return nil;
    }
    
    NSMutableData *amrData = [NSMutableData data];
    
    //编码
    const void *recordingData = pcmData.bytes;
    NSUInteger pcmLen = pcmData.length;
    
    if (pcmLen<=0){
        return nil;
    }
    if (pcmLen%2!=0){
        pcmLen--; //防止意外，如果不是偶数，情愿减去最后一个字节。
        NSLog(@"不是偶数");
    }
    
    unsigned char buffer[320];
    for (int i =0; i < pcmLen ;i+=160*2) {
        short *pPacket = (short *)((unsigned char*)recordingData+i);
//        if (pcmLen-i<160*2){
//            continue; //不是一个完整的就拜拜
//        }
        
        memset(buffer, 0, sizeof(buffer));
        //encode
        int recvLen = Encoder_Interface_Encode(destate,MR475,pPacket,buffer,0);
       
        //tcp传输方式所以加tcp头
//        nLen = recvLen + sizeof(RTP_header);
        nLen = recvLen;
        unsigned char amrBuf[336];
        memset(amrBuf, 0, sizeof(amrBuf));
		amrBuf[0] = '$';
		amrBuf[1] = 2;
		amrBuf[2] = nLen>>8;
		amrBuf[3] = nLen&0xff;
		memcpy(amrBuf+4,&rtpHead,sizeof(RTP_header));
		memcpy(amrBuf+4+sizeof(RTP_header),buffer,recvLen);
        
		nSLen = sizeof(RTP_header) + 4 + recvLen;

        if (recvLen>0) {
            NSData *data = [NSData dataWithBytes:amrBuf length:nSLen];
            [amrData appendData:data];
        }
    }

    return amrData;
}

- (NSData *)decodeAMRDataToPCMData:(NSData *)amrData
{
	void *destate;
	int nFrameCount = 0;
	int stdFrameSize;
    int nTemp;
    char bErr = 0;
    unsigned char stdFrameHeader;
    
    unsigned char amrFrame[MAX_AMR_FRAME_SIZE];
	short pcmFrame[PCM_FRAME_SIZE];
    
    if (amrData.length <= 0) {
        return nil;
    }
    
    const char* rfile = [amrData bytes];
    int maxLen = [amrData length];
    int pos = 0;
   
    NSMutableData* pcmData = [[NSMutableData alloc]init];
    
    /* init decoder */
	destate = Decoder_Interface_init();
    
    // 读第一帧 - 作为参考帧
	memset(amrFrame, 0, sizeof(amrFrame));
	memset(pcmFrame, 0, sizeof(pcmFrame));
    
    //参数一次是接收到的amr数据,下次开始点,一个amrFrame,帧大小 帧头
    nTemp = ReadAMRFrameFirstData(rfile,pos,maxLen, amrFrame, &stdFrameSize, &stdFrameHeader);
    if (nTemp==0) {
        Decoder_Interface_exit(destate);
        return nil;
    }
    pos += nTemp;
    // 解码一个AMR音频帧成PCM数据
	Decoder_Interface_Decode(destate, amrFrame, pcmFrame, 0);
	nFrameCount++;
	//fwrite(pcmFrame, sizeof(short), PCM_FRAME_SIZE, fpwave);
    [pcmData appendBytes:pcmFrame length:PCM_FRAME_SIZE*sizeof(short)];
    
    // 逐帧解码AMR并写到pcmData里
	while(1)
    {
		memset(amrFrame, 0, sizeof(amrFrame));
		memset(pcmFrame, 0, sizeof(pcmFrame));
		//if (!ReadAMRFrame(fpamr, amrFrame, stdFrameSize, stdFrameHeader)) break;
        
        nTemp = ReadAMRFrameData(rfile,pos,maxLen, amrFrame, stdFrameSize, stdFrameHeader);
        if (!nTemp) {bErr = 1;break;}
        pos += nTemp;
		
		// 解码一个AMR音频帧成PCM数据 (8k-16b-单声道)
		Decoder_Interface_Decode(destate, amrFrame, pcmFrame, 0);
		nFrameCount++;
		//fwrite(pcmFrame, sizeof(short), PCM_FRAME_SIZE, fpwave);
        [pcmData appendBytes:pcmFrame length:PCM_FRAME_SIZE*sizeof(short)];
    }
//	NSLog(@"frame = %d", nFrameCount);
	Decoder_Interface_exit(destate);
    
    return pcmData;
}

// 读第一个帧 - (参考帧)
// 返回值: 0-出错; 1-正确
int ReadAMRFrameFirstData(char* fpamr,int pos,int maxLen, unsigned char frameBuffer[], int* stdFrameSize, unsigned char* stdFrameHeader)
{
    int nPos = 0;
	memset(frameBuffer, 0, sizeof(frameBuffer));//一帧amr数据
	//去掉rtp包的16个字节
	if(fpamr[0] == '$'){
        nPos = 16;
    }
    else{
        return 0;//不是rtp包
    }
    // 先读帧头
    stdFrameHeader[0] = fpamr[nPos];
    nPos++;
    
    if (pos+nPos >= maxLen) {
        return 0;
    }
	
	// 根据帧头计算帧大小
	*stdFrameSize = caclAMRFrameSize(*stdFrameHeader);
	
	// 读首帧
	frameBuffer[0] = *stdFrameHeader;
    if ((*stdFrameSize-1)*sizeof(unsigned char)<=0) {
        return 0;
    }
    
    memcpy(&(frameBuffer[1]), fpamr+pos+nPos, (*stdFrameSize-1)*sizeof(unsigned char));
	//fread(&(frameBuffer[1]), 1, (*stdFrameSize-1)*sizeof(unsigned char), fpamr);
	//if (feof(fpamr)) return 0;
    nPos += (*stdFrameSize-1)*sizeof(unsigned char);
    if (pos+nPos >= maxLen) {
        return 0;
    }
	
	return nPos;
}

int ReadAMRFrameData(char* fpamr,int pos,int maxLen, unsigned char frameBuffer[], int stdFrameSize, unsigned char stdFrameHeader)
{
    int nPos = 0;
	unsigned char frameHeader; // 帧头
	
	memset(frameBuffer, 0, sizeof(frameBuffer));
	
	// 读帧头
	// 如果是坏帧(不是标准帧头)，则继续读下一个字节，直到读到标准帧头
	while(1)
    {
		//去掉rtp包的16个字节
        if(fpamr[0] == '$'){
            nPos = 16;
        }
        else{
            return 0;//不是rtp包
        }

        if (pos+nPos >=maxLen) {
            return 0;
        }
        frameHeader = fpamr[pos+nPos]; pos++;
		if (frameHeader == stdFrameHeader) break;
    }
	
	// 读该帧的语音数据(帧头已经读过)
	frameBuffer[0] = frameHeader;
	//bytes = fread(&(frameBuffer[1]), 1, (stdFrameSize-1)*sizeof(unsigned char), fpamr);
	//if (feof(fpamr)) return 0;
    if ((stdFrameSize-1)*sizeof(unsigned char)<=0) {
        return 0;
    }
	memcpy(&(frameBuffer[1]), fpamr+pos+nPos, (stdFrameSize-1)*sizeof(unsigned char));
    nPos += (stdFrameSize-1)*sizeof(unsigned char);
    if (pos+nPos >= maxLen) {
        return 0;
    }
    
	return nPos;
}


// 根据帧头计算当前帧大小
int caclAMRFrameSize(unsigned char frameHeader)
{
	int mode;
	int temp1 = 0;
	int temp2 = 0;
	int frameSize;
    int amrEncodeMode[] = {4750, 5150, 5900, 6700, 7400, 7950, 10200, 12200}; // amr 编码方式
	
	temp1 = frameHeader;
	
	// 编码方式编号 = 帧头的3-6位
	temp1 &= 0x78; // 0111-1000
	temp1 >>= 3;
	
	mode = amrEncodeMode[temp1];
	
	// 计算amr音频数据帧大小
	// 原理: amr 一帧对应20ms，那么一秒有50帧的音频数据
	temp2 = myround((double)(((double)mode / (double)AMR_FRAME_COUNT_PER_SECOND) / (double)8));
	
	frameSize = myround((double)temp2 + 0.5);
	return frameSize;
}

//decode

const int myround(const double x)
{
	return((int)(x+0.5));
}


@end
