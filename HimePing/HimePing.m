//
//  HimePing.m
//  HimePing
//
//  Created by S.C. on 2017/7/1.
//  Copyright © 2017年 Mitsuha. All rights reserved.
//

#import <arpa/inet.h>
#import "HimePing.h"

@interface HimePing ()

@property (nonatomic, assign) int               socket;
@property (nonatomic, assign) BOOL              isPinging;
@property (nonatomic, assign) NSTimeInterval    interval;
@property (nonatomic, assign) NSUInteger        sequence;

@property (nonatomic, strong) dispatch_queue_t  send4Queue;
@property (nonatomic, strong) dispatch_queue_t  receive4Queue;
@property (nonatomic, strong) dispatch_source_t send4Source;
@property (nonatomic, strong) dispatch_source_t receive4Source;

@property (nonatomic, copy  ) NSData            *hostAddress;
@property (nonatomic, copy  ) NSString          *hostAddressString;
@property (nonatomic, strong) NSMutableArray    *identifierArray;

@end

static const NSTimeInterval kDefaultTimeOut  = 1.0;
static const NSTimeInterval kDefaultInterval = 2.0;
static const int kBufferSize                 = 65535;
static const NSString *kDefaultHostString    = @"www.apple.com";

@implementation HimePing

#pragma mark - initialization

- (void)dealloc {
    if (!self.isPinging) {
        dispatch_resume(self.send4Source);
    }
    dispatch_source_cancel(self.send4Source);
    dispatch_source_cancel(self.receive4Source);
    if (self.socket) {
        close(self.socket);
    }
}

- (instancetype)init {
    if (self = [super init]) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithInterval:(NSTimeInterval)interval {
    if (self = [super init]) {
        _interval = interval;
        [self setup];
    }
    return self;
}

- (void)setup {
    self.sequence        = 0;
    self.identifierArray = [NSMutableArray array];
    self.socket          = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    self.send4Queue      = dispatch_queue_create("com.himePing.send4Queue", DISPATCH_QUEUE_SERIAL);
    self.receive4Queue   = dispatch_queue_create("com.himePing.receive4Queue", DISPATCH_QUEUE_SERIAL);
    
    __weak id weakSelf = self;
    self.receive4Source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.socket, 0, self.receive4Queue);
    dispatch_source_set_event_handler(self.receive4Source, ^{
        __strong id strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf receivePing];
        }
    });
    dispatch_resume(self.receive4Source);
    
    self.send4Source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.send4Queue);
    dispatch_source_set_timer(self.send4Source, DISPATCH_TIME_NOW, self.interval * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(self.send4Source, ^{
        __strong id strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf pingOnce];
        }
    });
}

#pragma mark - ping action

- (void)pingOnce {
    [self fetchAddressIP];
    NSData *packet = [self constructICMPPackage];
    ssize_t t = sendto(self.socket, packet.bytes, packet.length, 0, (struct sockaddr *)self.hostAddress.bytes, (socklen_t)self.hostAddress.length);
    //error
    if (t < 0) {
        NSError *error;
        if (!self.hostAddress) {
            error = [NSError errorWithDomain:@"Host data does not exist" code:HimePingErrorNoHostData userInfo:nil];
        } else {
            error = [NSError errorWithDomain:@"Socket send ping fail" code:HimePingErrorSend userInfo:nil];
        }
        [self.delegate pingDidError:error];
    }
    if (t > 0) {
        [self.delegate pingDidsend];
        ICMPHeader icmp;
        [packet getBytes:&icmp length:sizeof(ICMPHeader)];
        NSNumber *seq = @(icmp.identifier);
        [self.identifierArray addObject:seq];
        //check timeout
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeout * NSEC_PER_SEC)), self.send4Queue, ^{
            if ([self.identifierArray containsObject:seq]) {
                [self.delegate pingDidTimeOut];
                [self.identifierArray removeObject:seq];
            }
        });
    }
}

- (void)pingInfinitely {
    if (self.isPinging) {
        return;
    }
    self.isPinging = YES;
    dispatch_resume(self.send4Source);
}

- (void)stopPing {
    if (self.isPinging) {
        dispatch_suspend(self.send4Source);
        self.isPinging = NO;
    }
}

/**
 接受Ping
 */
- (void)receivePing {
    struct sockaddr_storage addr;
    socklen_t               addrLen;
    ssize_t                 bytesRead;
    void *                  buffer;
    buffer = malloc(kBufferSize);
    addrLen = sizeof(addr);
    
    bytesRead = recvfrom(self.socket, buffer, kBufferSize, 0, (struct sockaddr *)&addr, &addrLen);
    //error
    if (bytesRead < 0) {
        NSError *error = [NSError errorWithDomain:@"Receive pong fail" code:HimePingErrorReceive userInfo:nil];
        [self.delegate pingDidError:error];
        free(buffer);
        return;
    }
    
    //解析IP
    char hoststr[INET6_ADDRSTRLEN];
    struct sockaddr_in *sin = (struct sockaddr_in *)&addr;
    inet_ntop(sin->sin_family, &(sin->sin_addr), hoststr, INET6_ADDRSTRLEN);
    NSString *host = [[NSString alloc] initWithUTF8String:hoststr];
    NSLog(@"%@", host);
    
    //不是ping的地址
    if (![host isEqualToString:self.hostAddressString]) {
        free(buffer);
        return;
    }
    //不是响应ping
    NSMutableData *packet = [NSMutableData dataWithBytes:buffer length:(NSUInteger)bytesRead];
    const struct ICMPHeader *result = (const struct ICMPHeader *)((const uint8_t *)packet.bytes + sizeof(IPHeader));
    if (result->type != 0) {
        free(buffer);
        return;
    }
    NSNumber *seq = @(result->identifier);
    if ([self.identifierArray containsObject:seq]) {
        [self.identifierArray removeObject:seq];
        [self.delegate pindDidReceive];
    }
    free(buffer);
}

#pragma mark - getter & setter

- (NSTimeInterval)timeout {
    if (!_timeout) {
        return kDefaultTimeOut;
    } else {
        return _timeout;
    }
}

- (NSTimeInterval)interval {
    if (!_interval) {
        return kDefaultInterval;
    } else {
        return _interval;
    }
}

#pragma mark -

/**
 获取并设置IP地址
 */
- (void)fetchAddressIP {
    NSString *hostname = self.host ? : kDefaultHostString;
    CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)hostname);
    if (!hostRef) {
        return;
    }
    
    Boolean result = CFHostStartInfoResolution(hostRef, kCFHostAddresses, NULL);
    if (result == FALSE) {
        CFRelease(hostRef);
        return;
    }
    
    NSArray *addresses = (__bridge NSArray *)CFHostGetAddressing(hostRef, &result);
    for(int i = 0; i < addresses.count; i++) {
        struct sockaddr_in *remoteAddr;
        CFDataRef saData = (CFDataRef)CFArrayGetValueAtIndex((__bridge CFArrayRef)addresses, i);
        remoteAddr = (struct sockaddr_in *)CFDataGetBytePtr(saData);
        
        if(remoteAddr != NULL) {
            const char *strIP41 = inet_ntoa(remoteAddr->sin_addr);
            
            NSString *strDNS = [NSString stringWithCString:strIP41 encoding:NSASCIIStringEncoding];
            NSLog(@"Solved IP: %@", strDNS);
            self.hostAddressString = strDNS;
            
            NSData *dsa = [NSData dataWithBytes:remoteAddr length:remoteAddr->sin_len];
            self.hostAddress = dsa;
            break;
        }
    }
    CFRelease(hostRef);
}

/**
 构建ICMP报文
 */
- (NSData *)constructICMPPackage {
    NSMutableData *packet;
    ICMPHeader *icmpHeader;
    
    packet                 = [NSMutableData dataWithLength:sizeof(*icmpHeader)];
    icmpHeader             = packet.mutableBytes;
    icmpHeader->type       = 8;
    icmpHeader->code       = 0;
    icmpHeader->checksum   = 0;
    icmpHeader->identifier = OSSwapHostToBigInt16(arc4random());
    icmpHeader->sequence   = OSSwapHostToBigInt16(self.sequence);
    icmpHeader->checksum   = checksum(packet.bytes, packet.length);
    
    self.sequence += 1;
    return packet;
}

/**
 校验和算法
 */
static uint16_t checksum(const uint16_t *data_address, uint16_t data_length) {
    
    uint32_t data_check = 0;
    
    //每次累加两个字节数据
    while (data_length > 1) {
        data_check  += *data_address++;
        data_length -= sizeof(uint16_t);
    }
    
    //若剩余单个字节数据 加上
    if (data_length == 1) {
        data_check += *(uint8_t *)data_address;
    }
    
    //高16位 低16位相加 直至高16位为0
    while (data_check >> 16) {
        data_check = (data_check >> 16) + (data_check & 0xffff);
    }
    
    //取反返回
    return (uint16_t)~data_check;
}

@end
