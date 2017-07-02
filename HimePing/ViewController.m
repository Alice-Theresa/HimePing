//
//  ViewController.m
//  HimePing
//
//  Created by S.C. on 2017/7/1.
//  Copyright © 2017年 Mitsuha. All rights reserved.
//

#import "ViewController.h"

#import "HimePing.h"

@interface ViewController () <HimePingDelegate>

@property (nonatomic, strong) HimePing *ping;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (IBAction)start:(id)sender {
    if (self.ping) {
        [self.ping pingInfinitely];
    } else {
        self.ping = [[HimePing alloc] init];
        self.ping.delegate = self;
        [self.ping pingInfinitely];
    }
}

- (IBAction)stopPing:(id)sender {
    [self.ping stopPing];
}

- (IBAction)clean:(id)sender {
    self.ping = nil;
}

- (void)pindDidReceive {
    NSLog(@"receice pong");
}

- (void)pingDidError:(NSError *)error {
    NSLog(@"ping error : %@", error.domain);
}

- (void)pingDidTimeOut {
    NSLog(@"ping timeout");
}

- (void)pingDidsend {
    NSLog(@"send ping");
}


@end
