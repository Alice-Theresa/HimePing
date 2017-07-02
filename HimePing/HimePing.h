//
//  HimePing.h
//  HimePing
//
//  Created by S.C. on 2017/7/1.
//  Copyright © 2017年 Mitsuha. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct ICMPHeader {
    uint8_t     type;
    uint8_t     code;
    uint16_t    checksum;
    uint16_t    identifier;
    uint16_t    sequence;
} ICMPHeader;

typedef struct IPHeader {
    uint8_t     versionAndHeader;
    uint8_t     services;
    uint16_t    totalLength;
    uint16_t    identification;
    uint16_t    flagsAndOffset;
    uint8_t     ttl;
    uint8_t     protocol;
    uint16_t    checksum;
    uint8_t     sourceAddress[4];
    uint8_t     destinationAddress[4];
} IPHeader;

typedef NS_ENUM(NSInteger, HimePingError) {
    HimePingErrorSend = 10001,
    HimePingErrorReceive,
    HimePingErrorNoHostData,
};

@protocol HimePingDelegate <NSObject>

- (void)pingDidError:(NSError *)error;
- (void)pingDidsend;
- (void)pingDidTimeOut;
- (void)pindDidReceive;

@end

@interface HimePing : NSObject

@property (nonatomic, copy  ) NSString *host;  //默认苹果官网
@property (nonatomic, assign) NSTimeInterval timeout;  //超时默认1s
@property (nonatomic, weak  ) id<HimePingDelegate> delegate;

/**
 若要自定义无限Ping的时间间隔，则需调用此初始化方法，默认2s
 */
- (instancetype)initWithInterval:(NSTimeInterval)interval;

/**
 Ping一次
 */
- (void)pingOnce;

/**
 无限Ping
 */
- (void)pingInfinitely;

/**
 停止无限Ping
 */
- (void)stopPing;

@end
