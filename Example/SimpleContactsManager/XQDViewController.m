//
//  XQDViewController.m
//  SimpleContactsManager
//
//  Created by acct<blob>=<NULL> on 06/30/2017.
//  Copyright (c) 2017 acct<blob>=<NULL>. All rights reserved.
//

#import "XQDViewController.h"
#import <SimpleContactsManager/SimpleContactsManager.h>

@interface XQDViewController ()

@end

@implementation XQDViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
//    for(int i = 0; i < 5000;i++) {
//        [XQDContactsManager add];
//    }

	// Do any additional setup after loading the view, typically from a nib.
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [XQDContactsManager showPickerController:^{
        NSLog(@"deny authorization!!");
    } cancel:^{
        NSLog(@"user cancel operation!!");
    } detail:^(NSDictionary *detail) {
         NSLog(@"detail = %@", detail);
    } allContacts:^(NSArray *allContacts) {
        NSLog(@"all = %@", allContacts);
    }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
